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

    func testComparisonPinsReferencesAndRejectsRevisionExpressions() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let base = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "topic"])
        let topic = try repo.commit("topic", content: "topic", file: "topic.txt")
        try repo.git(["tag", "-a", "v1", "-m", "version"])
        try repo.git(["checkout", "main"])
        let main = try repo.commit("main", content: "main", file: "main.txt")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let before = try await workspace.snapshot()
        let comparison = try await workspace.comparison(fromReference: "refs/heads/main", toReference: "refs/tags/v1")
        XCTAssertEqual(comparison.from, main)
        XCTAssertEqual(comparison.to, topic)
        let files = try await workspace.changedFiles(in: comparison)
        XCTAssertEqual(Set(files.map(\.path)), ["main.txt", "topic.txt"])
        let after = try await workspace.snapshot()
        XCTAssertEqual(after, before)
        try repo.git(["update-ref", "refs/heads/main", base])
        try repo.git(["tag", "-d", "v1"])
        let retained = try await workspace.changedFiles(in: comparison)
        XCTAssertEqual(retained, files, "A captured comparison must not follow refs that moved or disappeared")
        for reference in ["refs/tags/v1", "--all", "main", "refs/heads/topic~1"] {
            do {
                _ = try await workspace.commitID(forReference: reference)
                XCTFail("Only exact existing references are accepted")
            } catch let error as WorkspaceFailure { XCTAssertEqual(error.key, "git.error.referenceMissing") }
        }
    }

    func testSelectionAnalysisUsesActualParentsNotFilteredRowAdjacency() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let root = try repo.commit("visible root", content: "one")
        let middle = try repo.commit("hidden middle", content: "two")
        let head = try repo.commit("visible head", content: "three")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let before = try await workspace.snapshot()
        let filtered = try await workspace.searchHistory(.init(text: "visible", field: .message))
        let gap = try await workspace.selectionSummary(for: filtered.commits)
        XCTAssertFalse(gap.isContiguous)
        XCTAssertEqual(gap.mainline, .all)
        XCTAssertEqual(gap.squashBlockedReason, "git.error.contiguous")
        XCTAssertNil(gap.rebaseBlockedReason)
        let all = try await workspace.history()
        let pair = try await workspace.selectionSummary(for: all.commits.filter { $0.id == head || $0.id == middle })
        XCTAssertTrue(pair.isContiguous)
        XCTAssertNil(pair.squashBlockedReason)
        let rootSelection = try await workspace.selectionSummary(for: all.commits)
        XCTAssertTrue(rootSelection.isContiguous)
        XCTAssertNil(rootSelection.rebaseBlockedReason)
        let after = try await workspace.snapshot()
        XCTAssertEqual(before, after)
        XCTAssertEqual(all.commits.last?.id, root)
    }

    func testSelectionAnalysisReportsSideBranchAndMergeInAffectedRange() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let base = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "topic"])
        let topic = try repo.commit("topic", content: "topic", file: "topic.txt")
        try repo.git(["checkout", "main"])
        _ = try repo.commit("main", content: "main", file: "main.txt")
        let workspace = try await GitWorkspace.open(at: repo.url)
        var page = try await workspace.history()
        let side = try await workspace.selectionSummary(for: page.commits.filter { $0.id == topic })
        XCTAssertEqual(side.mainline, .notAll)
        XCTAssertEqual(side.rebaseBlockedReason, "git.error.ancestry")
        try repo.git(["merge", "--no-ff", "topic", "-m", "Merge"])
        page = try await workspace.history()
        let selection = try await workspace.selectionSummary(for: page.commits.filter { $0.id == base })
        XCTAssertEqual(selection.mergeCount, 0)
        XCTAssertEqual(selection.rebaseBlockedReason, "git.error.merge", "A newer merge also prevents linear replay")
        let merge = try await workspace.selectionSummary(for: Array(page.commits.prefix(1)))
        XCTAssertEqual(merge.mergeCount, 1)
        XCTAssertFalse(merge.isContiguous)
    }

    func testSelectionBeyondMainlineBudgetIsUnknownRatherThanOutsideBranch() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        var stream = ""
        for index in 0..<10_002 {
            let message = "Commit \(index)"
            stream += "commit refs/heads/main\ncommitter Example <example@example.invalid> 1700000000 +0000\ndata \(message.utf8.count)\n\(message)\n\n"
        }
        let input = repo.url.appendingPathComponent("import.txt")
        try stream.write(to: input, atomically: true, encoding: .utf8)
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = repo.url
        process.arguments = ["fast-import", "--quiet"]
        process.standardInput = handle
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let workspace = try await GitWorkspace.open(at: repo.url)
        let history = try await workspace.history(limit: 10_002)
        let oldest = try XCTUnwrap(history.commits.last)
        let outsideBudget = try await workspace.selectionSummary(for: [oldest])
        XCTAssertEqual(outsideBudget.mainline, .unknown)
        XCTAssertEqual(outsideBudget.rebaseBlockedReason, "git.selectionAnalysisLimited")
        let latest = try await workspace.selectionSummary(for: Array(history.commits.prefix(2)))
        XCTAssertEqual(latest.mainline, .all)
        XCTAssertTrue(latest.isContiguous)
        XCTAssertNil(latest.squashBlockedReason)
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
