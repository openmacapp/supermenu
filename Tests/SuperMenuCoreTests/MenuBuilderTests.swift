import XCTest
@testable import SuperMenuCore

final class MenuBuilderTests: XCTestCase {
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
        let nodes = MenuBuilder.build(context: context, config: .standard, installedBundleIDs: installed)
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
        let nodes = MenuBuilder.build(context: context, config: .standard, installedBundleIDs: installedWithoutGoLand)
        let goLand = flatten(nodes).first { $0.title.contains("GoLand") }
        XCTAssertEqual(goLand?.title, "GoLand（未安装）")
        XCTAssertEqual(goLand?.enabled, false)
    }

    func testBlankFinderBackgroundCopiesTheFolderAndCanCreateFile() {
        let folder = URL(fileURLWithPath: "/tmp/project")
        let context = MenuContext(kind: .container, targetedFolder: folder, selection: [])
        let nodes = MenuBuilder.build(context: context, config: .standard, installedBundleIDs: installed)
        let commands = flatten(nodes)
        XCTAssertEqual(commands.first { $0.command == .builtin(.copyAbsolute) }?.enabled, true)
        XCTAssertEqual(commands.first { $0.title == "Swift" }?.enabled, true)
        XCTAssertEqual(commands.first { $0.command == .sendCopy(targetID: "desktop") }?.enabled, false)
        XCTAssertFalse(commands.contains { $0.command == .builtin(.openITerm) && $0.title.contains("未安装") })
    }

    func testDisabledCommandsDisappear() {
        var config = MenuConfig.standard
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
        XCTAssertEqual(nodes.map(\.title), ["复制相对路径", "复制终端路径", "复制文件名", "复制文件名（不含扩展名）"])
        XCTAssertFalse(nodes.contains { if case .separator = $0.kind { return true }; return false })
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
