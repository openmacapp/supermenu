import Foundation

public struct MenuNode: Equatable, Identifiable {
    public enum Kind: Equatable {
        case command(MenuCommand)
        case submenu(children: [MenuNode])
        case separator
    }

    public var id: String
    public var title: String
    public var kind: Kind
    public var isEnabled: Bool

    public init(id: String, title: String, kind: Kind, isEnabled: Bool) {
        self.id = id
        self.title = title
        self.kind = kind
        self.isEnabled = isEnabled
    }
}

public enum MenuBuilder {
    public static func build(
        context: MenuContext,
        config: MenuConfig,
        installedBundleIDs: Set<String>,
        fileManager: FileManager = .default
    ) -> [MenuNode] {
        let l10n = L10n(language: config.language)
        let paths = PathCommands.pathTargets(context)
        let hasPath = !paths.isEmpty
        let hasSelection = !context.selection.isEmpty
        var nodes: [MenuNode] = []

        func appendGroup(id: String, titleKey: String, children: [MenuNode]) {
            guard !children.isEmpty else { return }
            nodes.append(MenuNode(id: id, title: l10n.text(titleKey), kind: .submenu(children: children), isEnabled: true))
        }

        var copyGroup: [MenuNode] = []
        if config.copyAbsolute {
            copyGroup.append(command(.builtin(.copyAbsolute), title: l10n.text("copy.absolute"), enabled: hasPath))
        }
        if config.copyRelative {
            copyGroup.append(command(.builtin(.copyRelative), title: l10n.text("copy.relative"), enabled: hasPath))
        }
        if config.copyShell {
            copyGroup.append(command(.builtin(.copyShell), title: l10n.text("copy.shell"), enabled: hasPath))
        }
        if config.copyName {
            copyGroup.append(command(.builtin(.copyName), title: l10n.text("copy.name"), enabled: hasPath))
        }
        if config.copyStem {
            copyGroup.append(command(.builtin(.copyStem), title: l10n.text("copy.stem"), enabled: hasPath))
        }
        appendGroup(id: "sub:copy", titleKey: "copy.heading", children: copyGroup)

        let openChildren = openWithNodes(config: config, installedBundleIDs: installedBundleIDs, hasPath: hasPath)

        var terminalGroup: [MenuNode] = []
        if config.terminal {
            let installed = installedBundleIDs.contains("com.apple.Terminal")
            terminalGroup.append(command(
                .builtin(.openTerminal),
                title: installed ? l10n.text("open.terminal") : l10n.text("app.unavailable", l10n.text("open.terminal")),
                enabled: hasPath && installed
            ))
        }
        if config.iTerm && installedBundleIDs.contains("com.googlecode.iterm2") {
            terminalGroup.append(command(.builtin(.openITerm), title: l10n.text("open.iterm"), enabled: hasPath))
        }
        appendGroup(id: "sub:open", titleKey: "open.heading", children: join([openChildren, terminalGroup]))

        let newChildren = newFileNodes(context: context, config: config, fileManager: fileManager)
        appendGroup(id: "sub:new", titleKey: "new.heading", children: newChildren)

        let sendChildren = sendNodes(config: config, hasSelection: hasSelection)
        appendGroup(id: "sub:send", titleKey: "send.heading", children: sendChildren)

        var toolGroup: [MenuNode] = []
        if config.hashes {
            let file = isSingleFile(context: context, fileManager: fileManager)
            toolGroup.append(command(.builtin(.hashMD5), title: l10n.text("hash.md5"), enabled: file))
            toolGroup.append(command(.builtin(.hashSHA256), title: l10n.text("hash.sha256"), enabled: file))
        }
        if config.toggleHidden {
            toolGroup.append(command(.builtin(.toggleHidden), title: l10n.text("item.toggleHidden"), enabled: hasSelection))
        }
        if config.folderFromName {
            toolGroup.append(command(.builtin(.folderFromName), title: l10n.text("item.folderFromName"), enabled: context.selection.count == 1))
        }
        appendGroup(id: "sub:tools", titleKey: "tools.heading", children: toolGroup)

        return nodes
    }

    private static func openWithNodes(config: MenuConfig, installedBundleIDs: Set<String>, hasPath: Bool) -> [MenuNode] {
        let l10n = L10n(language: config.language)
        return config.openWith.compactMap { app in
            guard app.enabled else { return nil }
            let installed = app.bundleIDs.contains { installedBundleIDs.contains($0) }
            let title = installed ? app.displayName : l10n.text("app.unavailable", app.displayName)
            return command(.openApp(bundleIDs: app.bundleIDs), title: title, enabled: installed && hasPath)
        }
    }

    private static func newFileNodes(context: MenuContext, config: MenuConfig, fileManager: FileManager) -> [MenuNode] {
        let l10n = L10n(language: config.language)
        let canCreate = FileActions.creationDirectory(context: context, fileManager: fileManager) != nil
        return config.newFileTypes.compactMap { template in
            guard template.enabled else { return nil }
            return command(.newFile(templateID: template.id), title: l10n.title(for: template), enabled: canCreate)
        }
    }

    private static func sendNodes(config: MenuConfig, hasSelection: Bool) -> [MenuNode] {
        let l10n = L10n(language: config.language)
        return config.sendTargets.flatMap { target -> [MenuNode] in
            guard target.enabled else { return [] }
            return [
                command(.sendCopy(targetID: target.id), title: l10n.text("send.copy", l10n.title(for: target)), enabled: hasSelection),
                command(.sendMove(targetID: target.id), title: l10n.text("send.move", l10n.title(for: target)), enabled: hasSelection)
            ]
        }
    }

    private static func isSingleFile(context: MenuContext, fileManager: FileManager) -> Bool {
        guard context.selection.count == 1 else { return false }
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: context.selection[0].path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    private static func command(_ command: MenuCommand, title: String, enabled: Bool) -> MenuNode {
        MenuNode(id: command.token, title: title, kind: .command(command), isEnabled: enabled)
    }

    private static func join(_ groups: [[MenuNode]]) -> [MenuNode] {
        var nodes: [MenuNode] = []
        for group in groups where !group.isEmpty {
            if !nodes.isEmpty {
                nodes.append(MenuNode(id: "sep:\(nodes.count)", title: "", kind: .separator, isEnabled: true))
            }
            nodes.append(contentsOf: group)
        }
        return nodes
    }
}
