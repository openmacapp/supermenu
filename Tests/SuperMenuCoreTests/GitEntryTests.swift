import XCTest
@testable import SuperMenuCore

final class GitEntryTests: XCTestCase {
    func testGitURLRoundTripsPathsAndDoesNotAcceptActions() throws {
        let path = URL(fileURLWithPath: "/tmp/仓库 'quote' & more/#?%.swift")
        let url = try XCTUnwrap(GitLaunchURL.make(path))
        XCTAssertEqual(GitLaunchURL.directory(from: url), path)
        XCTAssertNil(GitLaunchURL.directory(from: URL(string: "supermenu://git?path=/tmp&action=reset")!))
        XCTAssertNil(GitLaunchURL.directory(from: URL(string: "supermenu://git?path=relative")!))
        XCTAssertNil(GitLaunchURL.directory(from: URL(string: "https://git?path=/tmp")!))
    }

    func testGitEntryOnlyAppearsForSingleRepositoryPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func nodes(_ selection: [URL]) -> [MenuNode] {
            MenuBuilder.build(context: MenuContext(kind: .container, targetedFolder: directory, selection: selection),
                              config: .standard, installedBundleIDs: [])
        }
        XCTAssertFalse(nodes([]).contains { $0.kind == .command(.builtin(.gitHistory)) })
        // Linked worktrees use a .git file, not a directory.
        try "gitdir: /tmp/example".write(to: directory.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertTrue(nodes([]).contains { $0.kind == .command(.builtin(.gitHistory)) })
        XCTAssertFalse(nodes([directory, directory.appendingPathComponent("another")]).contains { $0.kind == .command(.builtin(.gitHistory)) })
    }
}
