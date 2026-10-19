import AppKit
import Foundation
import OSLog

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

final class MenuRenderer {
    private var tagsByToken: [String: Int] = [:]
    private var commandsByTag: [Int: MenuCommand] = [:]

    func command(for item: NSMenuItem) -> MenuCommand? {
        commandsByTag[item.tag]
    }

    func menu(from nodes: [MenuNode], target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for node in nodes {
            menu.addItem(item(from: node, target: target, action: action))
        }
        return menu
    }

    private func item(from node: MenuNode, target: AnyObject, action: Selector) -> NSMenuItem {
        switch node.kind {
        case .separator:
            return .separator()
        case .command(let command):
            let item = NSMenuItem(title: node.title, action: action, keyEquivalent: "")
            item.tag = tag(for: command)
            item.isEnabled = node.isEnabled
            item.target = target
            item.image = MenuIcons.image(for: node)
            return item
        case .submenu(let children):
            let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
            item.submenu = menu(from: children, target: target, action: action)
            item.image = MenuIcons.image(for: node)
            return item
        }
    }

    private func tag(for command: MenuCommand) -> Int {
        if let tag = tagsByToken[command.token] { return tag }
        // Finder transfers tag, but not representedObject. Never reuse a tag
        // for another command: an older menu may still be awaiting its click.
        let tag = commandsByTag.count + 1
        tagsByToken[command.token] = tag
        commandsByTag[tag] = command
        return tag
    }
}

enum CommandRunner {
    private static let logger = Logger(subsystem: "org.openmacapp.supermenu", category: "Commands")

    static func run(_ command: MenuCommand, context: MenuContext, config: MenuConfig, presentErrors: Bool) {
        let l10n = L10n(language: config.language)
        do {
            switch command {
            case .builtin(let builtin):
                try runBuiltin(builtin, context: context, config: config, presentErrors: presentErrors)
            case .openApp(let bundleIDs):
                try open(bundleIDs: bundleIDs, urls: PathCommands.pathTargets(context), presentErrors: presentErrors, localization: l10n)
            case .newFile(let templateID):
                guard let template = config.newFileTypes.first(where: { $0.id == templateID }) else {
                    throw ActionError(l10n.text("error.template"))
                }
                guard let directory = FileActions.creationDirectory(context: context) else {
                    throw ActionError(l10n.text("error.creationFolder"))
                }
                _ = try FileActions.createFile(template: template, in: directory, localization: l10n)
            case .sendCopy(let targetID):
                try send(targetID: targetID, context: context, config: config, move: false)
            case .sendMove(let targetID):
                try send(targetID: targetID, context: context, config: config, move: true)
            }
        } catch let error as ActionError {
            fail(error.message, presentErrors: presentErrors, localization: l10n)
        } catch {
            fail(error.localizedDescription, presentErrors: presentErrors, localization: l10n)
        }
    }

    private static func runBuiltin(_ command: BuiltinCommand, context: MenuContext, config: MenuConfig, presentErrors: Bool) throws {
        let l10n = L10n(language: config.language)
        let paths = PathCommands.pathTargets(context)
        switch command {
        case .gitHistory:
            guard paths.count == 1, let path = paths.first,
                  let url = GitLaunchURL.make(path),
                  let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.openmacapp.supermenu") else {
                throw ActionError(l10n.text("error.noSelection"))
            }
            let options = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: options) { _, error in
                if let error {
                    DispatchQueue.main.async { fail(error.localizedDescription, presentErrors: presentErrors, localization: l10n) }
                }
            }
        case .copyAbsolute:
            try requirePaths(paths, localization: l10n)
            paste(PathCommands.absoluteText(paths))
        case .copyRelative:
            try requirePaths(paths, localization: l10n)
            paste(PathCommands.relativeText(urls: paths, finderFolder: context.targetedFolder, config: config))
        case .copyShell:
            try requirePaths(paths, localization: l10n)
            paste(PathCommands.shellText(paths))
        case .copyName:
            try requirePaths(paths, localization: l10n)
            paste(PathCommands.nameText(paths))
        case .copyStem:
            try requirePaths(paths, localization: l10n)
            paste(PathCommands.stemText(paths))
        case .openTerminal:
            try openTerminal(bundleID: "com.apple.Terminal", urls: paths, presentErrors: presentErrors, localization: l10n)
        case .openITerm:
            try openTerminal(bundleID: "com.googlecode.iterm2", urls: paths, presentErrors: presentErrors, localization: l10n)
        case .hashMD5:
            paste(try hash(context: context, algorithm: .md5, localization: l10n))
        case .hashSHA256:
            paste(try hash(context: context, algorithm: .sha256, localization: l10n))
        case .toggleHidden:
            guard !context.selection.isEmpty else { throw ActionError(l10n.text("error.noSelection")) }
            for url in context.selection {
                _ = try FileActions.toggleHidden(of: url)
            }
        case .folderFromName:
            guard context.selection.count == 1, let url = context.selection.first else {
                throw ActionError(l10n.text("error.selectOneItem"))
            }
            _ = try FileActions.folderFromName(of: url)
        }
    }

    private static func requirePaths(_ urls: [URL], localization l10n: L10n) throws {
        if urls.isEmpty { throw ActionError(l10n.text("error.noSelection")) }
    }

    private static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func hash(context: MenuContext, algorithm: HashAlgorithm, localization l10n: L10n) throws -> String {
        guard context.selection.count == 1, let url = context.selection.first else {
            throw ActionError(l10n.text("error.selectOneFile"))
        }
        return try FileActions.hash(of: url, algorithm: algorithm, localization: l10n)
    }

    private static func send(targetID: String, context: MenuContext, config: MenuConfig, move: Bool) throws {
        let l10n = L10n(language: config.language)
        guard !context.selection.isEmpty else { throw ActionError(l10n.text("error.noSelection")) }
        guard let target = config.sendTargets.first(where: { $0.id == targetID }) else {
            throw ActionError(l10n.text("error.sendTarget"))
        }
        let directory = PathCommands.expandPath(target.directory, home: FileManager.default.homeDirectoryForCurrentUser)
        _ = try FileActions.placeItems(context.selection, into: directory, move: move, localization: l10n)
    }

    private static func open(bundleIDs: [String], urls: [URL], presentErrors: Bool, localization l10n: L10n) throws {
        guard !urls.isEmpty else { throw ActionError(l10n.text("error.noSelection")) }
        guard let appURL = InstalledApps.url(for: bundleIDs) else { throw ActionError(l10n.text("error.appMissing")) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { app, error in
            if let error {
                let nsError = error as NSError
                logger.error("Open failed: \(nsError.domain, privacy: .public) code=\(nsError.code)")
                DispatchQueue.main.async {
                    fail(error.localizedDescription, presentErrors: presentErrors, localization: l10n)
                }
            } else {
                logger.notice("Open accepted by \(app?.bundleIdentifier ?? "unknown", privacy: .public), items=\(urls.count)")
            }
        }
    }

    private static func openTerminal(bundleID: String, urls: [URL], presentErrors: Bool, localization l10n: L10n) throws {
        guard let directory = terminalDirectory(for: urls) else { throw ActionError(l10n.text("error.noSelection")) }
        // Both Terminal and iTerm register public.folder with Launch Services.
        // Passing a URL also handles quotes in paths without shell/AppleScript interpolation.
        try open(bundleIDs: [bundleID], urls: [directory], presentErrors: presentErrors, localization: l10n)
    }

    private static func terminalDirectory(for urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return first
        }
        return first.deletingLastPathComponent()
    }

    private static func fail(_ message: String, presentErrors: Bool, localization l10n: L10n) {
        logger.error("Command failed: \(message, privacy: .private)")
        NSSound.beep()
        guard presentErrors else { return }
        let alert = NSAlert()
        alert.messageText = l10n.text("app.name")
        alert.informativeText = message
        alert.runModal()
    }
}
