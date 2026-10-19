import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    var description: String
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw CheckFailure(description: "\(message): got \(actual), expected \(expected)")
    }
}

func run() throws {
    for command in BuiltinCommand.allCases {
        try checkEqual(MenuCommand.parse(MenuCommand.builtin(command).token), .builtin(command), command.rawValue)
    }
    let open = MenuCommand.openApp(bundleIDs: ["com.microsoft.VSCode"])
    try checkEqual(MenuCommand.parse(open.token), open, "open token")
    try check(MenuCommand.parse("nope") == nil, "unknown token")

    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("supermenu-check-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
    let file = root.appendingPathComponent("src/a.go")
    FileManager.default.createFile(atPath: file.path, contents: Data("package main\n".utf8))

    try checkEqual(PathCommands.stemText([file]), "a", "stem")
    try checkEqual(PathCommands.shellQuote("/tmp/a'b.txt"), "'/tmp/a'\\''b.txt'", "shell quote")
    var config = MenuConfig.standard
    config.relativeMode = .gitRoot
    try checkEqual(
        PathCommands.relativeText(urls: [file], finderFolder: root.appendingPathComponent("src"), config: config),
        "src/a.go",
        "git relative"
    )
    config.relativeMode = .finderFolder
    try checkEqual(
        PathCommands.relativeText(urls: [file], finderFolder: root.appendingPathComponent("src"), config: config),
        "a.go",
        "finder relative"
    )
    config.relativeMode = .gitRoot
    config.extraRoots = [root.appendingPathComponent("src").path]
    try checkEqual(PathCommands.relativeText(urls: [file], finderFolder: root, config: config), "a.go", "extra root")

    let elsewhere = URL(fileURLWithPath: "/tmp/outside-\(UUID().uuidString).txt")
    try checkEqual(
        PathCommands.relativeText(urls: [elsewhere], finderFolder: root, config: MenuConfig.standard),
        elsewhere.standardizedFileURL.path,
        "absolute fallback"
    )

    try checkEqual(FileActions.uniqueChildName(stem: "未命名", ext: "txt", existing: ["未命名.txt", "未命名 2.txt"]), "未命名 3.txt", "unique name")
    let template = NewFileTemplate(id: "json", title: "JSON", ext: "json", contents: "{}\n", enabled: true)
    let created = try FileActions.createFile(template: template, in: root)
    try checkEqual(created.lastPathComponent, "未命名.json", "created name")
    try checkEqual(try String(contentsOf: created, encoding: .utf8), "{}\n", "created contents")

    let abc = root.appendingPathComponent("abc.txt")
    FileManager.default.createFile(atPath: abc.path, contents: Data("abc".utf8))
    try checkEqual(try FileActions.hash(of: abc, algorithm: .md5), "900150983cd24fb0d6963f7d28e17f72", "md5")
    try checkEqual(
        try FileActions.hash(of: abc, algorithm: .sha256),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "sha256"
    )
    let empty = root.appendingPathComponent("empty.txt")
    FileManager.default.createFile(atPath: empty.path, contents: Data())
    try checkEqual(try FileActions.hash(of: empty, algorithm: .md5), "d41d8cd98f00b204e9800998ecf8427e", "empty md5")
    do {
        _ = try FileActions.hash(of: root, algorithm: .sha256)
        throw CheckFailure(description: "directory hash should fail")
    } catch is ActionError {
    }

    let report = root.appendingPathComponent("report.pdf")
    FileManager.default.createFile(atPath: report.path, contents: Data("x".utf8))
    let folder = try FileActions.folderFromName(of: report)
    try checkEqual(folder.lastPathComponent, "report", "folder from name")
    let hidden = try FileActions.toggleHidden(of: report)
    try check(hidden, "hide")
    let shown = try FileActions.toggleHidden(of: report)
    try check(!shown, "show")

    let installed: Set<String> = [
        "com.microsoft.VSCode",
        "com.jetbrains.goland",
        "com.todesktop.230313mzl4w4u92",
        "com.tencent.workbuddy.mac",
        "com.apple.Terminal",
        "com.googlecode.iterm2"
    ]
    let context = MenuContext(kind: .items, targetedFolder: root, selection: [file])
    let titles = flatten(MenuBuilder.build(context: context, config: .standard, installedBundleIDs: installed)).map(\.title)
    for title in ["复制绝对路径", "复制相对路径", "Visual Studio Code", "GoLand", "Cursor", "WorkBuddy", "文本文件"] {
        try check(titles.contains(title), "missing menu item \(title)")
    }
    let withoutGoLand = installed.filter { $0 != "com.jetbrains.goland" }
    let goLand = flatten(MenuBuilder.build(context: context, config: .standard, installedBundleIDs: withoutGoLand))
        .first { $0.title.contains("GoLand") }
    try checkEqual(goLand?.title, "GoLand（未安装）", "missing goland title")
    try checkEqual(goLand?.enabled, false, "missing goland disabled")

    let blank = MenuContext(kind: .container, targetedFolder: root, selection: [])
    let blankCommands = flatten(MenuBuilder.build(context: blank, config: .standard, installedBundleIDs: installed))
    try checkEqual(blankCommands.first { $0.command == .builtin(.copyAbsolute) }?.enabled, true, "blank copy")
    try checkEqual(blankCommands.first { $0.command == .sendCopy(targetID: "desktop") }?.enabled, false, "blank send")

    let stored = FileManager.default.temporaryDirectory.appendingPathComponent("supermenu-config-\(UUID().uuidString).json")
    try Data("{\"copyAbsolute\":false}".utf8).write(to: stored)
    let loaded = ConfigStore.load(from: stored)
    try check(!loaded.copyAbsolute && loaded.copyRelative, "partial config")
    try checkEqual(loaded.openWith.map(\.displayName), ["Visual Studio Code", "GoLand", "Cursor", "WorkBuddy"], "default apps")
    try ConfigStore.save(loaded, to: stored)
    try checkEqual(ConfigStore.load(from: stored), loaded, "round trip")
    try? FileManager.default.removeItem(at: stored)
}

func flatten(_ nodes: [MenuNode]) -> [(title: String, command: MenuCommand, enabled: Bool)] {
    nodes.flatMap { node -> [(title: String, command: MenuCommand, enabled: Bool)] in
        switch node.kind {
        case .command(let command):
            return [(node.title, command, node.isEnabled)]
        case .submenu(let children):
            return flatten(children)
        case .separator:
            return []
        }
    }
}

do {
    try run()
    print("ok")
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(1)
}
