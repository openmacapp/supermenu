import Foundation

public enum GitBadgeFailure: Error { case unavailable, overBudget, malformed, changed }

public struct GitBadgeIdentity: Equatable, Sendable {
    public let root: URL
    public let gitDirectory: URL
    public let commonDirectory: URL
    public var key: String { root.path + "\0" + gitDirectory.path }
}

public struct GitBadgeSnapshot: Sendable {
    public let states: [String: String]
    /// Conservative allocation estimate including ancestor keys and hash storage.
    public let cost: Int
}

/// Independent of diff/history: only status metadata enters the app. Git may
/// inspect working files to compute status; no contents enter our diff renderer.
public enum GitBadgeStatus {
    public static let inputLimit = 2 * 1024 * 1024
    public static let snapshotLimit = 4 * 1024 * 1024

    public static func discover(at directory: URL) async throws -> GitBadgeIdentity {
        func path(_ option: String) async throws -> URL {
            let result = try await BoundedGitRead.read(
                root: directory,
                arguments: ["rev-parse", "--path-format=absolute", option], byteLimit: 16 * 1024)
            guard !result.truncated, var text = String(data: result.data, encoding: .utf8),
                text.hasSuffix("\n")
            else { throw GitBadgeFailure.unavailable }
            text.removeLast()  // A newline may legitimately occur inside a path.
            guard text.hasPrefix("/"), !text.contains("\0") else { throw GitBadgeFailure.unavailable }
            return URL(fileURLWithPath: text).standardizedFileURL.resolvingSymlinksInPath()
        }
        return try await GitBadgeIdentity(
            root: path("--show-toplevel"),
            gitDirectory: path("--absolute-git-dir"),
            commonDirectory: path("--git-common-dir"))
    }

    public static func read(_ identity: GitBadgeIdentity) async throws -> GitBadgeSnapshot {
        let before = try fingerprint(identity)
        let result = try await BoundedGitRead.read(
            root: identity.root,
            arguments: [
                "--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false",
                "-c", "core.quotePath=false", "-c", "submodule.recurse=false",
                "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=dirty",
                "--no-renames",
            ], byteLimit: inputLimit)
        guard !result.truncated else { throw GitBadgeFailure.overBudget }
        try Task.checkCancellation()
        let snapshot = try parse(result.data, byteBudget: snapshotLimit - 128 * 1024)
        guard try fingerprint(identity) == before else { throw GitBadgeFailure.changed }
        return snapshot
    }

    public static func parse(
        _ data: Data, byteBudget: Int = snapshotLimit,
        recordLimit: Int = 20_000
    ) throws -> GitBadgeSnapshot {
        guard data.count <= inputLimit else { throw GitBadgeFailure.overBudget }
        guard data.isEmpty || data.last == 0 else { throw GitBadgeFailure.malformed }
        var states: [String: String] = [:]
        var cost = 1024
        var start = data.startIndex
        var records = 0
        func next() throws -> String {
            guard let end = data[start...].firstIndex(of: 0), end - start <= 4099,
                let value = String(data: data[start..<end], encoding: .utf8)
            else { throw GitBadgeFailure.malformed }
            start = end + 1
            return value
        }
        func add(_ rawPath: String, state: String) throws {
            let path = rawPath.hasSuffix("/") ? String(rawPath.dropLast()) : rawPath
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.isEmpty, !path.hasPrefix("/"),
                parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
            else { throw GitBadgeFailure.malformed }
            var ancestor = path
            while true {
                if let old = states[ancestor] {
                    if priority(state) > priority(old) { states[ancestor] = state }
                } else {
                    let entryCost = 256 + ancestor.utf8.count * 4
                    guard cost <= byteBudget - entryCost else { throw GitBadgeFailure.overBudget }
                    cost += entryCost
                    states[ancestor] = state
                }
                if ancestor == "." { break }
                if let slash = ancestor.lastIndex(of: "/") {
                    ancestor = String(ancestor[..<slash])
                } else {
                    ancestor = "."
                }
            }
        }
        while start < data.endIndex {
            try Task.checkCancellation()
            records += 1
            guard records <= recordLimit else { throw GitBadgeFailure.overBudget }
            let record = try next()
            let bytes = Array(record.utf8.prefix(3))
            guard bytes.count == 3, bytes[2] == 32,
                bytes.prefix(2).allSatisfy({ Array(" MADRCUT?!".utf8).contains($0) })
            else { throw GitBadgeFailure.malformed }
            let code = String(record.prefix(2))
            let path = String(record.dropFirst(3))
            let state =
                ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains(code)
                ? "conflict"
                : (code == "??" ? "untracked" : "modified")
            if code != "!!" { try add(path, state: state) }
            if code.contains("R") || code.contains("C") { try add(next(), state: "modified") }
        }
        return GitBadgeSnapshot(states: states, cost: cost)
    }
    private static func priority(_ state: String) -> Int {
        state == "conflict" ? 3 : (state == "modified" ? 2 : 1)
    }
    private static func fingerprint(_ identity: GitBadgeIdentity) throws -> [String] {
        let manager = FileManager.default
        var paths = [
            identity.root, identity.gitDirectory, identity.commonDirectory,
            identity.gitDirectory.appendingPathComponent("HEAD"),
            identity.gitDirectory.appendingPathComponent("index"),
        ]
        let head = identity.gitDirectory.appendingPathComponent("HEAD")
        let handle = try FileHandle(forReadingFrom: head)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 4096) ?? Data()
        if let ref = String(data: bytes, encoding: .utf8), ref.hasPrefix("ref: ") {
            let name = ref.dropFirst(5).trimmingCharacters(in: .newlines)
            if name.hasPrefix("refs/"), !name.split(separator: "/").contains("..") {
                paths.append(identity.commonDirectory.appendingPathComponent(name))
            }
        }
        var result = [bytes.base64EncodedString()]
        for (index, url) in paths.enumerated() {
            if let attributes = try? manager.attributesOfItem(atPath: url.path) {
                result.append(
                    "\(attributes[.systemNumber] ?? 0):\(attributes[.systemFileNumber] ?? 0):\(attributes[.size] ?? 0):\(attributes[.modificationDate] ?? 0)"
                )
            } else if index < 4 {
                throw GitBadgeFailure.unavailable
            } else {
                result.append("missing")
            }
        }
        return result
    }
}
