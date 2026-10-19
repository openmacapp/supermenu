import AppKit
import Foundation

enum InstalledApps {
    static func bundleIDs(referencedBy config: MenuConfig) -> Set<String> {
        var ids: [String] = ["com.apple.Terminal", "com.googlecode.iterm2"]
        for app in config.openWith {
            ids.append(contentsOf: app.bundleIDs)
        }
        return Set(ids.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
    }

    static func url(for bundleIDs: [String]) -> URL? {
        for id in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url
            }
        }
        return nil
    }
}

enum MenuRenderer {
    static func menu(from nodes: [MenuNode], target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for node in nodes {
            menu.addItem(item(from: node, target: target, action: action))
        }
        return menu
    }

    private static func item(from node: MenuNode, target: AnyObject, action: Selector) -> NSMenuItem {
        switch node.kind {
        case .separator:
            return .separator()
        case .command(let command):
            let item = NSMenuItem(title: node.title, action: action, keyEquivalent: "")
            item.representedObject = command.token
            item.isEnabled = node.isEnabled
            item.target = target
            return item
        case .submenu(let children):
            let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
            item.submenu = menu(from: children, target: target, action: action)
            return item
        }
    }
}

enum CommandRunner {
    static func run(_ command: MenuCommand, context: MenuContext, config: MenuConfig, presentErrors: Bool) {
        do {
            switch command {
            case .builtin(let builtin):
                try runBuiltin(builtin, context: context, config: config)
            case .openApp(let bundleIDs):
                try open(bundleIDs: bundleIDs, urls: PathCommands.pathTargets(context))
            case .newFile(let templateID):
                guard let template = config.newFileTypes.first(where: { $0.id == templateID }) else {
                    throw ActionError("找不到要新建的文件类型")
                }
                guard let directory = FileActions.creationDirectory(context: context) else {
                    throw ActionError("没有可以新建文件的文件夹")
                }
                _ = try FileActions.createFile(template: template, in: directory)
            case .sendCopy(let targetID):
                try send(targetID: targetID, context: context, config: config, move: false)
            case .sendMove(let targetID):
                try send(targetID: targetID, context: context, config: config, move: true)
            }
        } catch let error as ActionError {
            fail(error.message, presentErrors: presentErrors)
        } catch {
            fail(error.localizedDescription, presentErrors: presentErrors)
        }
    }

    private static func runBuiltin(_ command: BuiltinCommand, context: MenuContext, config: MenuConfig) throws {
        let paths = PathCommands.pathTargets(context)
        switch command {
        case .copyAbsolute:
            try requirePaths(paths)
            paste(PathCommands.absoluteText(paths))
        case .copyRelative:
            try requirePaths(paths)
            paste(PathCommands.relativeText(urls: paths, finderFolder: context.targetedFolder, config: config))
        case .copyShell:
            try requirePaths(paths)
            paste(PathCommands.shellText(paths))
        case .copyName:
            try requirePaths(paths)
            paste(PathCommands.nameText(paths))
        case .copyStem:
            try requirePaths(paths)
            paste(PathCommands.stemText(paths))
        case .openTerminal:
            try openTerminal(bundleID: "com.apple.Terminal", urls: paths, useITerm: false)
        case .openITerm:
            try openTerminal(bundleID: "com.googlecode.iterm2", urls: paths, useITerm: true)
        case .hashMD5:
            paste(try hash(context: context, algorithm: .md5))
        case .hashSHA256:
            paste(try hash(context: context, algorithm: .sha256))
        case .toggleHidden:
            guard !context.selection.isEmpty else { throw ActionError("没有选中文件") }
            for url in context.selection {
                _ = try FileActions.toggleHidden(of: url)
            }
        case .folderFromName:
            guard context.selection.count == 1, let url = context.selection.first else {
                throw ActionError("请选中一个文件或文件夹")
            }
            _ = try FileActions.folderFromName(of: url)
        }
    }

    private static func requirePaths(_ urls: [URL]) throws {
        if urls.isEmpty { throw ActionError("没有选中文件") }
    }

    private static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func hash(context: MenuContext, algorithm: HashAlgorithm) throws -> String {
        guard context.selection.count == 1, let url = context.selection.first else {
            throw ActionError("请选中一个文件")
        }
        return try FileActions.hash(of: url, algorithm: algorithm)
    }

    private static func send(targetID: String, context: MenuContext, config: MenuConfig, move: Bool) throws {
        guard !context.selection.isEmpty else { throw ActionError("没有选中文件") }
        guard let target = config.sendTargets.first(where: { $0.id == targetID }) else {
            throw ActionError("找不到发送目标")
        }
        let directory = PathCommands.expandPath(target.directory, home: FileManager.default.homeDirectoryForCurrentUser)
        _ = try FileActions.placeItems(context.selection, into: directory, move: move)
    }

    private static func open(bundleIDs: [String], urls: [URL]) throws {
        guard !urls.isEmpty else { throw ActionError("没有选中文件") }
        guard let appURL = InstalledApps.url(for: bundleIDs) else { throw ActionError("没有安装对应的 App") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
    }

    private static func openTerminal(bundleID: String, urls: [URL], useITerm: Bool) throws {
        guard let directory = terminalDirectory(for: urls) else { throw ActionError("没有选中文件") }
        if useITerm {
            let source = """
            tell application "iTerm"
              activate
              set newWindow to (create window with default profile)
              tell current session of newWindow
                write text "cd \(PathCommands.shellQuote(directory.path))"
              end tell
            end tell
            """
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { throw ActionError("无法打开 iTerm") }
            script.executeAndReturnError(&error)
            if let message = error?[NSAppleScript.errorMessage] as? String {
                throw ActionError(message)
            }
            return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ActionError("没有安装终端")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([directory], withApplicationAt: appURL, configuration: configuration)
    }

    private static func terminalDirectory(for urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return first
        }
        return first.deletingLastPathComponent()
    }

    private static func fail(_ message: String, presentErrors: Bool) {
        NSSound.beep()
        guard presentErrors else { return }
        let alert = NSAlert()
        alert.messageText = "超级右键"
        alert.informativeText = message
        alert.runModal()
    }
}
