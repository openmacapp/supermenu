import Foundation

public enum MenuSurface: String, Equatable {
    case items
    case container
    case sidebar
    case toolbar
}

public struct MenuContext: Equatable {
    public var kind: MenuSurface
    public var targetedFolder: URL?
    public var selection: [URL]

    public init(kind: MenuSurface, targetedFolder: URL?, selection: [URL]) {
        self.kind = kind
        self.targetedFolder = targetedFolder
        self.selection = selection
    }
}

public enum PathCommands {
    public static func pathTargets(_ context: MenuContext) -> [URL] {
        if !context.selection.isEmpty { return context.selection }
        if let folder = context.targetedFolder { return [folder] }
        return []
    }

    public static func absoluteText(_ urls: [URL]) -> String {
        urls.map { $0.standardizedFileURL.path }.joined(separator: "\n")
    }

    public static func nameText(_ urls: [URL]) -> String {
        urls.map(\.lastPathComponent).joined(separator: "\n")
    }

    public static func stemText(_ urls: [URL]) -> String {
        urls.map { stem(of: $0.lastPathComponent) }.joined(separator: "\n")
    }

    public static func shellText(_ urls: [URL]) -> String {
        urls.map { shellQuote($0.standardizedFileURL.path) }.joined(separator: "\n")
    }

    public static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func relativeText(
        urls: [URL],
        finderFolder: URL?,
        config: MenuConfig,
        fileManager: FileManager = .default
    ) -> String {
        let home = fileManager.homeDirectoryForCurrentUser
        let extraRoots = config.extraRoots.map { expandPath($0, home: home) }
        return urls.map { url in
            let anchor = anchor(
                for: url,
                finderFolder: finderFolder,
                mode: config.relativeMode,
                extraRoots: extraRoots,
                fileManager: fileManager
            )
            return relativePath(from: anchor, to: url) ?? url.standardizedFileURL.path
        }
        .joined(separator: "\n")
    }

    public static func relativePath(from anchor: URL, to target: URL) -> String? {
        let anchorPath = anchor.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        if targetPath == anchorPath { return "." }
        let prefix = anchorPath == "/" ? "/" : anchorPath + "/"
        guard targetPath.hasPrefix(prefix) else { return nil }
        return String(targetPath.dropFirst(prefix.count))
    }

    public static func gitRoot(containing url: URL, fileManager: FileManager = .default) -> URL? {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        var directory = url
        if exists && !isDirectory.boolValue {
            directory = url.deletingLastPathComponent()
        }
        while true {
            let git = directory.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: git.path) {
                return directory
            }
            if directory.path == "/" { return nil }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }

    public static func anchor(
        for target: URL,
        finderFolder: URL?,
        mode: RelativeAnchorMode,
        extraRoots: [URL],
        fileManager: FileManager = .default
    ) -> URL {
        let matches = extraRoots.filter { relativePath(from: $0, to: target) != nil }
        if let best = matches.max(by: { $0.standardizedFileURL.path.count < $1.standardizedFileURL.path.count }) {
            return best
        }
        switch mode {
        case .gitRoot:
            if let root = gitRoot(containing: target, fileManager: fileManager) {
                return root
            }
            return finderFolder ?? target.deletingLastPathComponent()
        case .finderFolder:
            return finderFolder ?? target.deletingLastPathComponent()
        }
    }

    public static func expandPath(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }

    public static func stem(of name: String) -> String {
        let ext = (name as NSString).pathExtension
        if ext.isEmpty { return name }
        return (name as NSString).deletingPathExtension
    }
}
