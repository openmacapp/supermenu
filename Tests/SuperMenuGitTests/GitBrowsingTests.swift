import XCTest
@testable import SuperMenuGit

final class GitBrowsingTests: XCTestCase {
    func testReferenceBrowsingDoesNotChangeRepository() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let base = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "feature/topic"])
        let topic = try repo.commit("topic", content: "topic")
        try repo.git(["tag", "-a", "v1", "-m", "Version one"])
        try repo.git(["update-ref", "refs/remotes/origin/topic", topic])
        try repo.git(["checkout", "main"])
        let main = try repo.commit("main", content: "main")
        try "pending".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let workspace = try await GitWorkspace.open(at: repo.url)
        let before = try await workspace.snapshot()
        let indexBefore = try repo.git(["ls-files", "--stage", "-z"])
        let refs = try await workspace.references()
        XCTAssertEqual(refs.filter(\.isHead).map(\.id), ["refs/heads/main"])
        XCTAssertEqual(Set(refs.map(\.id)), [
            "refs/heads/main", "refs/heads/feature/topic", "refs/remotes/origin/topic", "refs/tags/v1"
        ])
        for reference in ["refs/heads/feature/topic", "refs/remotes/origin/topic", "refs/tags/v1"] {
            let page = try await workspace.history(reference: reference)
            XCTAssertEqual(page.commits.map(\.id), [topic, base])
        }
        let all = try await workspace.history()
        XCTAssertEqual(Set(all.commits.map(\.id)), [main, topic, base])
        let after = try await workspace.snapshot()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try repo.git(["ls-files", "--stage", "-z"]), indexBefore)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "pending")
        try repo.git(["branch", "-D", "feature/topic"])
        for invalid in ["refs/heads/feature/topic", "--all", "main", "refs/heads/main~1"] {
            do {
                _ = try await workspace.history(reference: invalid)
                XCTFail("Missing or non-reference inputs must not silently show other history")
            } catch let error as WorkspaceFailure {
                XCTAssertEqual(error.key, "git.error.referenceMissing")
            }
        }
    }

    func testUnbornAndDetachedHistory() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let workspace = try await GitWorkspace.open(at: repo.url)
        let emptyRefs = try await workspace.references()
        let emptyHistory = try await workspace.history()
        XCTAssertTrue(emptyRefs.isEmpty)
        XCTAssertTrue(emptyHistory.commits.isEmpty)
        let commit = try repo.commit("base", content: "base")
        try repo.git(["checkout", "--detach", commit])
        let refs = try await workspace.references()
        let history = try await workspace.history()
        XCTAssertFalse(refs.contains(where: \.isHead))
        XCTAssertEqual(history.commits.map(\.id), [commit])
    }

    func testDirectoryCollapseAndRenameSearchPreserveLiteralPaths() {
        let files = [
            GitChangedFile(path: "src/deep/新\t文件.swift", oldPath: "old/renamed.swift", status: "R"),
            GitChangedFile(path: "src/root.swift", oldPath: nil, status: "M"),
            GitChangedFile(path: "README.md", oldPath: nil, status: "A")
        ]
        let tree = GitFileTree(files: files)
        XCTAssertEqual(tree.directories, ["src", "src/deep"])
        XCTAssertEqual(tree.rows(collapsed: ["src"]).map(\.path), ["src", "README.md"])
        let searched = tree.rows(collapsed: ["src", "src/deep"], query: "OLD/renamed")
        XCTAssertEqual(searched.map(\.path), ["src", "src/deep", files[0].path])
        XCTAssertEqual(searched.map(\.depth), [0, 1, 2])
        XCTAssertEqual(searched.last?.file, files[0])
        XCTAssertTrue(tree.rows(query: "missing").isEmpty)
    }

    func testLargeTreeUsesOnlyChangedPaths() {
        let files = (0..<5000).map { GitChangedFile(path: "src/group\($0 % 10)/file\($0).swift", oldPath: nil, status: "M") }
        let tree = GitFileTree(files: files)
        XCTAssertEqual(tree.directories.count, 11)
        XCTAssertEqual(tree.rows().count, 5011)
        XCTAssertEqual(tree.rows(collapsed: ["src"]).count, 1)
        XCTAssertEqual(tree.rows(query: "file4999.swift").map(\.path),
                       ["src", "src/group9", "src/group9/file4999.swift"])
    }

    func testSearchDistinguishesDeletedFileFromReplacementDirectory() {
        let tree = GitFileTree(files: [
            GitChangedFile(path: "config", oldPath: nil, status: "D"),
            GitChangedFile(path: "config/settings.json", oldPath: nil, status: "A")
        ])
        let rows = tree.rows(query: "settings")
        XCTAssertEqual(rows.compactMap(\.file).map(\.path), ["config/settings.json"])
        XCTAssertEqual(rows.filter { $0.file == nil }.map(\.path), ["config"])
    }
}
