import XCTest
@testable import SuperMenuCore

final class MenuBuilderTests: XCTestCase {
    private var chineseConfig: MenuConfig {
        var config = MenuConfig.standard
        config.language = .chinese
        return config
    }

    private let installed: Set<String> = [
        "com.microsoft.VSCode",
        "com.jetbrains.goland",
        "com.todesktop.230313mzl4w4u92",
        "com.tencent.workbuddy.mac",
        "com.apple.Terminal",
        "com.googlecode.iterm2"
    ]

    func testFileMenuOffersPathsEditorsAndNewFile() throws {
        let file = URL(fileURLWithPath: "/tmp/supermenu-missing-demo.go")
        let context = MenuContext(kind: .items, targetedFolder: URL(fileURLWithPath: "/tmp"), selection: [file])
        let nodes = MenuBuilder.build(context: context, config: chineseConfig, installedBundleIDs: installed)
        let commands = flatten(nodes)
        XCTAssertTrue(commands.contains { $0.command == .builtin(.copyAbsolute) && $0.enabled })
        XCTAssertTrue(commands.contains { $0.command == .builtin(.copyRelative) && $0.enabled })
        XCTAssertEqual(
            commands.filter { if case .openApp = $0.command { return true }; return false }.map(\.title),
            ["Visual Studio Code", "GoLand", "Cursor", "WorkBuddy"]
        )
        XCTAssertTrue(commands.contains { $0.title == "文本文件" && $0.enabled })
        XCTAssertTrue(commands.contains { $0.command == .builtin(.hashMD5) && !$0.enabled })
    }

    func testMissingEditorStaysVisibleAndDisabled() {
        let file = URL(fileURLWithPath: "/tmp/supermenu-missing-demo.go")
        let context = MenuContext(kind: .items, targetedFolder: URL(fileURLWithPath: "/tmp"), selection: [file])
        let installedWithoutGoLand = installed.filter { $0 != "com.jetbrains.goland" }
        let nodes = MenuBuilder.build(context: context, config: chineseConfig, installedBundleIDs: installedWithoutGoLand)
        let goLand = flatten(nodes).first { $0.title.contains("GoLand") }
        XCTAssertEqual(goLand?.title, "GoLand（未安装）")
        XCTAssertEqual(goLand?.enabled, false)
    }

    func testBlankFinderBackgroundCopiesTheFolderAndCanCreateFile() {
        let folder = URL(fileURLWithPath: "/tmp/project")
        let context = MenuContext(kind: .container, targetedFolder: folder, selection: [])
        let nodes = MenuBuilder.build(context: context, config: chineseConfig, installedBundleIDs: installed)
        let commands = flatten(nodes)
        XCTAssertEqual(commands.first { $0.command == .builtin(.copyAbsolute) }?.enabled, true)
        XCTAssertEqual(commands.first { $0.title == "Swift" }?.enabled, true)
        XCTAssertEqual(commands.first { $0.command == .sendCopy(targetID: "desktop") }?.enabled, false)
        XCTAssertFalse(commands.contains { $0.command == .builtin(.openITerm) && $0.title.contains("未安装") })
    }

    func testDisabledCommandsDisappear() {
        var config = chineseConfig
        config.copyAbsolute = false
        config.openWith = []
        config.newFileTypes = config.newFileTypes.map { template in
            var copy = template
            copy.enabled = false
            return copy
        }
        config.sendTargets = []
        config.terminal = false
        config.iTerm = false
        config.hashes = false
        config.toggleHidden = false
        config.folderFromName = false
        config.copyRelative = true
        let context = MenuContext(kind: .items, targetedFolder: nil, selection: [URL(fileURLWithPath: "/tmp/a")])
        let nodes = MenuBuilder.build(context: context, config: config, installedBundleIDs: installed)
        XCTAssertEqual(nodes.map(\.title), ["复制信息"])
        XCTAssertEqual(flatten(nodes).map(\.title), ["复制相对路径", "复制终端路径", "复制文件名", "复制文件名（不含扩展名）"])
        XCTAssertFalse(nodes.contains { if case .separator = $0.kind { return true }; return false })
    }

    func testMenuHasFiveCompactGroupsAndPreservesEveryCommand() {
        let context = MenuContext(kind: .items, targetedFolder: URL(fileURLWithPath: "/tmp"), selection: [URL(fileURLWithPath: "/tmp/example.txt")])
        let nodes = MenuBuilder.build(context: context, config: chineseConfig, installedBundleIDs: installed)
        XCTAssertEqual(nodes.map(\.title), ["复制信息", "打开方式", "新建", "发送到", "文件工具"])
        for node in nodes {
            guard case .submenu(let children) = node.kind else {
                return XCTFail("Every top-level entry should be a category")
            }
            XCTAssertFalse(children.isEmpty)
            if node.id == "sub:open" {
                let commands = flatten(children).map(\.command)
                XCTAssertEqual(commands.suffix(2), [.builtin(.openTerminal), .builtin(.openITerm)])
            }
        }
        let commands = flatten(nodes).map(\.command)
        let expected = BuiltinCommand.allCases.map(MenuCommand.builtin)
            + chineseConfig.openWith.map { .openApp(bundleIDs: $0.bundleIDs) }
            + chineseConfig.newFileTypes.map { .newFile(templateID: $0.id) }
            + chineseConfig.sendTargets.flatMap { [MenuCommand.sendCopy(targetID: $0.id), .sendMove(targetID: $0.id)] }
        XCTAssertEqual(commands.count, expected.count)
        XCTAssertEqual(Set(commands.map(\.token)), Set(expected.map(\.token)))
    }

    func testAllDisabledFeaturesProduceNoEmptyGroups() {
        var config = chineseConfig
        config.copyAbsolute = false
        config.copyRelative = false
        config.copyShell = false
        config.copyName = false
        config.copyStem = false
        config.openWith = []
        config.terminal = false
        config.iTerm = false
        config.newFileTypes = []
        config.sendTargets = []
        config.hashes = false
        config.toggleHidden = false
        config.folderFromName = false
        let context = MenuContext(kind: .container, targetedFolder: URL(fileURLWithPath: "/tmp"), selection: [])
        XCTAssertTrue(MenuBuilder.build(context: context, config: config, installedBundleIDs: installed).isEmpty)
        config.terminal = true
        let nodes = MenuBuilder.build(context: context, config: config, installedBundleIDs: installed)
        XCTAssertEqual(nodes.map(\.title), ["打开方式"])
        guard case .submenu(let children) = nodes.first?.kind else { return XCTFail("Missing open group") }
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(flatten(children).first?.command, .builtin(.openTerminal))
    }

    func testPartialConfigKeepsNewCommands() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("supermenu-config-\(UUID().uuidString).json")
        try Data("{\"copyAbsolute\":false}".utf8).write(to: url)
        let loaded = ConfigStore.load(from: url)
        XCTAssertFalse(loaded.copyAbsolute)
        XCTAssertTrue(loaded.copyRelative)
        XCTAssertEqual(loaded.openWith.map(\.displayName), ["Visual Studio Code", "GoLand", "Cursor", "WorkBuddy"])
        try ConfigStore.save(loaded, to: url)
        XCTAssertEqual(ConfigStore.load(from: url), loaded)
        try? FileManager.default.removeItem(at: url)
    }

    private func flatten(_ nodes: [MenuNode]) -> [(title: String, command: MenuCommand, enabled: Bool)] {
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
}
