import XCTest
@testable import SuperMenuCore

final class FileActionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("supermenu-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testUniqueNamesSkipTheFirstCollision() {
        let existing: Set<String> = ["未命名.txt", "未命名 2.txt"]
        XCTAssertEqual(FileActions.uniqueChildName(stem: "未命名", ext: "txt", existing: existing), "未命名 3.txt")
        XCTAssertEqual(FileActions.uniqueChildName(stem: "未命名", ext: "txt", existing: []), "未命名.txt")
    }

    func testCreateFileWritesTemplateAndAvoidsCollision() throws {
        let template = NewFileTemplate(id: "json", title: "JSON", ext: "json", contents: "{}\n", enabled: true)
        let first = try FileActions.createFile(template: template, in: root)
        let second = try FileActions.createFile(template: template, in: root)
        XCTAssertEqual(first.lastPathComponent, "未命名.json")
        XCTAssertEqual(second.lastPathComponent, "未命名 2.json")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "{}\n")
    }

    func testCopyAddsNumericSuffixWhenNameExists() throws {
        let source = root.appendingPathComponent("a.txt")
        FileManager.default.createFile(atPath: source.path, contents: Data("one".utf8))
        let destDir = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: destDir.appendingPathComponent("a.txt").path, contents: Data("old".utf8))
        let placed = try FileActions.placeItems([source], into: destDir, move: false)
        XCTAssertEqual(placed.map(\.lastPathComponent), ["a 2.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let moved = try FileActions.placeItems([source], into: destDir, move: true)
        XCTAssertEqual(moved.map(\.lastPathComponent), ["a 3.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testFolderFromNameAndToggleHidden() throws {
        let file = root.appendingPathComponent("report.pdf")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        let folder = try FileActions.folderFromName(of: file)
        XCTAssertEqual(folder.lastPathComponent, "report")
        XCTAssertTrue(try FileActions.toggleHidden(of: file))
        let values = try file.resourceValues(forKeys: [.isHiddenKey])
        XCTAssertEqual(values.isHidden, true)
        XCTAssertFalse(try FileActions.toggleHidden(of: file))
    }

    func testHashesMatchKnownVectors() throws {
        let file = root.appendingPathComponent("abc.txt")
        FileManager.default.createFile(atPath: file.path, contents: Data("abc".utf8))
        XCTAssertEqual(try FileActions.hash(of: file, algorithm: .md5), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(
            try FileActions.hash(of: file, algorithm: .sha256),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        let empty = root.appendingPathComponent("empty.txt")
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        XCTAssertEqual(try FileActions.hash(of: empty, algorithm: .md5), "d41d8cd98f00b204e9800998ecf8427e")
    }

    func testHashRejectsDirectory() {
        XCTAssertThrowsError(try FileActions.hash(of: root, algorithm: .sha256))
    }

    func testCreationDirectory() throws {
        let file = root.appendingPathComponent("a.go")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let folder = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileContext = MenuContext(kind: .items, targetedFolder: root, selection: [file])
        XCTAssertEqual(FileActions.creationDirectory(context: fileContext)?.path, root.path)
        let folderContext = MenuContext(kind: .items, targetedFolder: root, selection: [folder])
        XCTAssertEqual(FileActions.creationDirectory(context: folderContext)?.path, folder.path)
        let blank = MenuContext(kind: .container, targetedFolder: root, selection: [])
        XCTAssertEqual(FileActions.creationDirectory(context: blank)?.path, root.path)
    }
}
