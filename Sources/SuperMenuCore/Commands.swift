import Foundation

public enum BuiltinCommand: String, Codable, Equatable, CaseIterable {
    case copyAbsolute = "copy.absolute"
    case copyRelative = "copy.relative"
    case copyShell = "copy.shell"
    case copyName = "copy.name"
    case copyStem = "copy.stem"
    case openTerminal = "open.terminal"
    case openITerm = "open.iterm"
    case hashMD5 = "hash.md5"
    case hashSHA256 = "hash.sha256"
    case toggleHidden = "item.toggleHidden"
    case folderFromName = "item.folderFromName"
}

public enum MenuCommand: Equatable {
    case builtin(BuiltinCommand)
    case openApp(bundleIDs: [String])
    case newFile(templateID: String)
    case sendCopy(targetID: String)
    case sendMove(targetID: String)

    public var token: String {
        switch self {
        case .builtin(let command):
            return "builtin:\(command.rawValue)"
        case .openApp(let bundleIDs):
            return "open:\(bundleIDs.joined(separator: ","))"
        case .newFile(let templateID):
            return "new:\(templateID)"
        case .sendCopy(let targetID):
            return "send-copy:\(targetID)"
        case .sendMove(let targetID):
            return "send-move:\(targetID)"
        }
    }

    public static func parse(_ token: String) -> MenuCommand? {
        if let raw = token.suffix(after: "builtin:") {
            guard let command = BuiltinCommand(rawValue: raw) else { return nil }
            return .builtin(command)
        }
        if let raw = token.suffix(after: "open:") {
            let ids = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
            guard !ids.isEmpty else { return nil }
            return .openApp(bundleIDs: ids)
        }
        if let raw = token.suffix(after: "new:") {
            guard !raw.isEmpty else { return nil }
            return .newFile(templateID: raw)
        }
        if let raw = token.suffix(after: "send-copy:") {
            guard !raw.isEmpty else { return nil }
            return .sendCopy(targetID: raw)
        }
        if let raw = token.suffix(after: "send-move:") {
            guard !raw.isEmpty else { return nil }
            return .sendMove(targetID: raw)
        }
        return nil
    }
}

private extension String {
    func suffix(after prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
