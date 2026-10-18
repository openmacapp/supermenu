import XCTest
@testable import SuperMenuCore

final class PathTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("supermenu-paths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("src/a.go").path, contents: Data("package main\n".utf8))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAbsoluteAndShellQuote() {
        let file = root.appendingPathComponent("src/a.go")
        let odd = root.appendingPathComponent("a'b.txt")
        XCTAssertEqual(
            PathCommands.absoluteText([file, odd]),
            "\(file.standardizedFileURL.path)\n\(odd.standardizedFileURL.path)"
        )
        XCTAssertEqual(PathCommands.shellQuote("/tmp/a'b.txt"), "'/tmp/a'\\''b.txt'")
        XCTAssertEqual(PathCommands.nameText([file]), "a.go")
        XCTAssertEqual(PathCommands.stemText([file]), "a")
        XCTAssertEqual(PathCommands.stem(of: ".gitignore"), ".gitignore")
    }

    func testRelativeUsesGitRootBeforeFinderFolder() {
        let file = root.appendingPathComponent("src/a.go")
        var config = MenuConfig.standard
        config.relativeMode = .gitRoot
        let text = PathCommands.relativeText(
            urls: [file],
            finderFolder: root.appendingPathComponent("src"),
            config: config
        )
        XCTAssertEqual(text, "src/a.go")
    }

    func testRelativeUsesFinderFolderWhenAsked() {
        let file = root.appendingPathComponent("src/a.go")
        var config = MenuConfig.standard
        config.relativeMode = .finderFolder
        let text = PathCommands.relativeText(
            urls: [file],
            finderFolder: root.appendingPathComponent("src"),
            config: config
        )
        XCTAssertEqual(text, "a.go")
    }

    func testExtraRootWinsOverGit() {
        let file = root.appendingPathComponent("src/a.go")
        var config = MenuConfig.standard
        config.relativeMode = .gitRoot
        config.extraRoots = [root.appendingPathComponent("src").path]
        let text = PathCommands.relativeText(urls: [file], finderFolder: root, config: config)
        XCTAssertEqual(text, "a.go")
    }

    func testOutsideAnchorFallsBackToAbsolute() {
        let elsewhere = URL(fileURLWithPath: "/tmp/outside.txt")
        XCTAssertNil(PathCommands.relativePath(from: root, to: elsewhere))
        var config = MenuConfig.standard
        let text = PathCommands.relativeText(urls: [elsewhere], finderFolder: root, config: config)
        XCTAssertEqual(text, elsewhere.standardizedFileURL.path)
    }

    func testGitFileMarksRoot() throws {
        let worktree = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: worktree.appendingPathComponent(".git").path, contents: Data("gitdir: /x\n".utf8))
        let file = worktree.appendingPathComponent("main.go")
        XCTAssertEqual(PathCommands.gitRoot(containing: file)?.standardizedFileURL.path, worktree.standardizedFileURL.path)
    }

    func testBackgroundClickUsesFolder() {
        let context = MenuContext(kind: .container, targetedFolder: root, selection: [])
        XCTAssertEqual(PathCommands.pathTargets(context), [root])
        let selected = root.appendingPathComponent("src/a.go")
        let itemContext = MenuContext(kind: .items, targetedFolder: root, selection: [selected])
        XCTAssertEqual(PathCommands.pathTargets(itemContext), [selected])
    }

    func testExpandTilde() {
        let home = URL(fileURLWithPath: "/Users/example")
        XCTAssertEqual(PathCommands.expandPath("~/Desktop", home: home).path, "/Users/example/Desktop")
        XCTAssertEqual(PathCommands.expandPath("/tmp", home: home).path, "/tmp")
    }
}
