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
        let paths = PathCommands.pathTargets(context)
        let hasPath = !paths.isEmpty
        let hasSelection = !context.selection.isEmpty
        var groups: [[MenuNode]] = []

        var copyGroup: [MenuNode] = []
        if config.copyAbsolute {
            copyGroup.append(command(.builtin(.copyAbsolute), title: "复制绝对路径", enabled: hasPath))
        }
        if config.copyRelative {
            copyGroup.append(command(.builtin(.copyRelative), title: "复制相对路径", enabled: hasPath))
        }
        if config.copyShell {
            copyGroup.append(command(.builtin(.copyShell), title: "复制终端路径", enabled: hasPath))
        }
        if config.copyName {
            copyGroup.append(command(.builtin(.copyName), title: "复制文件名", enabled: hasPath))
        }
        if config.copyStem {
            copyGroup.append(command(.builtin(.copyStem), title: "复制文件名（不含扩展名）", enabled: hasPath))
        }
        if !copyGroup.isEmpty { groups.append(copyGroup) }

        let openChildren = openWithNodes(config: config, installedBundleIDs: installedBundleIDs, hasPath: hasPath)
        if !openChildren.isEmpty {
            groups.append([
                MenuNode(id: "sub:open", title: "打开方式", kind: .submenu(children: openChildren), isEnabled: true)
            ])
        }

        var terminalGroup: [MenuNode] = []
        if config.terminal {
            let installed = installedBundleIDs.contains("com.apple.Terminal")
            terminalGroup.append(command(
                .builtin(.openTerminal),
                title: installed ? "在终端中打开" : "在终端中打开（未安装）",
                enabled: hasPath && installed
            ))
        }
        if config.iTerm && installedBundleIDs.contains("com.googlecode.iterm2") {
            terminalGroup.append(command(.builtin(.openITerm), title: "在 iTerm 中打开", enabled: hasPath))
        }
        if !terminalGroup.isEmpty { groups.append(terminalGroup) }

        let newChildren = newFileNodes(context: context, config: config, fileManager: fileManager)
        if !newChildren.isEmpty {
            groups.append([
                MenuNode(id: "sub:new", title: "新建", kind: .submenu(children: newChildren), isEnabled: true)
            ])
        }

        let sendChildren = sendNodes(config: config, hasSelection: hasSelection)
        if !sendChildren.isEmpty {
            groups.append([
                MenuNode(id: "sub:send", title: "发送到", kind: .submenu(children: sendChildren), isEnabled: true)
            ])
        }

        var toolGroup: [MenuNode] = []
        if config.hashes {
            let file = isSingleFile(context: context, fileManager: fileManager)
            toolGroup.append(command(.builtin(.hashMD5), title: "拷贝 MD5", enabled: file))
            toolGroup.append(command(.builtin(.hashSHA256), title: "拷贝 SHA256", enabled: file))
        }
        if config.toggleHidden {
            toolGroup.append(command(.builtin(.toggleHidden), title: "显示/隐藏", enabled: hasSelection))
        }
        if config.folderFromName {
            toolGroup.append(command(.builtin(.folderFromName), title: "按文件名新建文件夹", enabled: context.selection.count == 1))
        }
        if !toolGroup.isEmpty { groups.append(toolGroup) }

        return join(groups)
    }

    private static func openWithNodes(config: MenuConfig, installedBundleIDs: Set<String>, hasPath: Bool) -> [MenuNode] {
        config.openWith.compactMap { app in
            guard app.enabled else { return nil }
            let installed = app.bundleIDs.contains { installedBundleIDs.contains($0) }
            let title = installed ? app.displayName : "\(app.displayName)（未安装）"
            return command(.openApp(bundleIDs: app.bundleIDs), title: title, enabled: installed && hasPath)
        }
    }

    private static func newFileNodes(context: MenuContext, config: MenuConfig, fileManager: FileManager) -> [MenuNode] {
        let canCreate = FileActions.creationDirectory(context: context, fileManager: fileManager) != nil
        return config.newFileTypes.compactMap { template in
            guard template.enabled else { return nil }
            return command(.newFile(templateID: template.id), title: template.title, enabled: canCreate)
        }
    }

    private static func sendNodes(config: MenuConfig, hasSelection: Bool) -> [MenuNode] {
        config.sendTargets.flatMap { target -> [MenuNode] in
            guard target.enabled else { return [] }
            return [
                command(.sendCopy(targetID: target.id), title: "复制到\(target.title)", enabled: hasSelection),
                command(.sendMove(targetID: target.id), title: "移动到\(target.title)", enabled: hasSelection)
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
