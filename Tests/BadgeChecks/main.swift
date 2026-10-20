import Darwin
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: " + message + "\n", stderr)
        exit(1)
    }
}
func git(_ arguments: [String], at root: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.currentDirectoryURL = root
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    var environment = ProcessInfo.processInfo.environment
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    environment["GIT_AUTHOR_NAME"] = "Example"
    environment["GIT_COMMITTER_NAME"] = "Example"
    environment["GIT_AUTHOR_EMAIL"] = "example@example.invalid"
    environment["GIT_COMMITTER_EMAIL"] = "example@example.invalid"
    process.environment = environment
    try process.run()
    process.waitUntilExit()
    require(process.terminationStatus == 0, "fixture git command")
}
func request(_ paths: [String], service: String, client: String) throws -> BadgeReply {
    let payload = try JSONEncoder().encode(BadgeRequest(client: client, paths: paths, touch: true))
    return try JSONDecoder().decode(BadgeReply.self, from: BadgeTransport.request(payload, name: service))
}
func waitFor(_ state: String?, path: String, service: String, client: String) throws {
    for _ in 0..<100 {
        if try request([path], service: service, client: client).states[path] == state { return }
        Thread.sleep(forTimeInterval: 0.1)
    }
    require(false, "expected status did not arrive")
}

let args = CommandLine.arguments
if args.count >= 3 && args[1] == "--serve" {
    let service = GitBadgeService()
    try service.start(name: args[2])
    dispatchMain()
} else if args.count >= 4 && args[1] == "--probe" {
    let client = UUID().uuidString
    try waitFor("untracked", path: args[3], service: args[2], client: client)
    print("PASS signed sandbox client received Git status")
} else {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "BadgeChecks-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try git(["init", "-b", "main"], at: root)
    let file = root.appendingPathComponent("file.txt")
    try "base".write(to: file, atomically: true, encoding: .utf8)
    try git(["add", "."], at: root)
    try git(["commit", "-m", "Base"], at: root)
    let name = "org.example.badges." + UUID().uuidString
    let service = GitBadgeService()
    try service.start(name: name)
    defer { service.stop() }
    let client = UUID().uuidString
    try "changed".write(to: file, atomically: true, encoding: .utf8)
    try waitFor("modified", path: file.path, service: name, client: client)
    print("PASS host status via authenticated Mach transport")
    if file.path.hasPrefix("/var/") {
        try waitFor("modified", path: "/private" + file.path, service: name, client: client)
        print("PASS equivalent macOS path aliases retain caller response keys")
    }
    try git(["checkout", "--", "file.txt"], at: root)
    // First wait for the event to be delivered; an empty response before initial
    // load is not sufficient evidence that the file became clean.
    Thread.sleep(forTimeInterval: 1)
    try waitFor(nil, path: file.path, service: name, client: client)
    try "changed again".write(to: file, atomically: true, encoding: .utf8)
    try waitFor("modified", path: file.path, service: name, client: client)
    print("PASS filesystem events invalidate and rebuild status")
    service.setEnabled(false)
    try waitFor(nil, path: file.path, service: name, client: client)
    require(service.diagnostics().bytes == 0, "disable releases cache")
    service.setEnabled(true)
    try waitFor("modified", path: file.path, service: name, client: client)
    print("PASS disable clears cache and re-enable recovers")
    for _ in 0..<100 { _ = try request([file.path], service: name, client: client) }
    require(service.diagnostics().bytes <= 24 * 1024 * 1024, "host memory accounting")
    require(service.diagnostics().scans < 10, "cache hits must not rescan")
    for _ in 0..<12 { _ = try request([file.path], service: name, client: UUID().uuidString) }
    require(service.diagnostics().clients <= 8, "multi-client admission")
    print("PASS 100 cached requests and bounded client leases")

    service.applyMemoryPressure(critical: true, normal: false)
    try waitFor(nil, path: file.path, service: name, client: client)
    require(service.diagnostics().bytes == 0, "critical pressure releases cache")
    service.applyMemoryPressure(critical: false, normal: true)
    try waitFor("modified", path: file.path, service: name, client: client)
    print("PASS critical pressure clears state and demand recovers after normal pressure")
    var repositoryPaths: [String] = []
    for index in 0..<18 {
        let directory = root.appendingPathComponent("repo-\(index)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try git(["init", "-q"], at: directory)
        repositoryPaths.append(directory.path)
        _ = try request([directory.path], service: name, client: client)
    }
    // Repeated admission and reset can evict a scan before its task starts.
    // A subsequent visible repository must still obtain a fresh snapshot.
    for _ in 0..<10 {
        _ = try request(repositoryPaths, service: name, client: client)
        service.invalidateAll()
    }
    try waitFor("modified", path: file.path, service: name, client: client)
    require(service.diagnostics().repositories <= 16, "repository admission limit")
    require(service.diagnostics().bytes <= 24 * 1024 * 1024, "repository cost limit")
    print("PASS 18 repositories stay bounded and scanning recovers after repeated eviction/reset")

    if let index = args.firstIndex(of: "--soak"), args.count > index + 1,
        let duration = Double(args[index + 1])
    {
        let end = ProcessInfo.processInfo.systemUptime + duration
        var iteration = 0
        while ProcessInfo.processInfo.systemUptime < end {
            _ = try request([file.path], service: name, client: client)
            if iteration % 15 == 0 {
                try "change \(iteration)".write(to: file, atomically: true, encoding: .utf8)
                let diagnostics = service.diagnostics()
                require(diagnostics.bytes <= 24 * 1024 * 1024, "soak accounting")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/ps")
                process.arguments = ["-o", "rss=,%cpu=", "-p", String(getpid())]
                try process.run()
                process.waitUntilExit()
                print(
                    "SOAK iteration=\(iteration) cache=\(diagnostics.bytes) scans=\(diagnostics.scans) failures=\(diagnostics.failures)"
                )
                fflush(stdout)
            }
            iteration += 1
            Thread.sleep(forTimeInterval: 2)
        }
        print("PASS sustained status refresh duration=\(duration)s iterations=\(iteration)")
    }
}
