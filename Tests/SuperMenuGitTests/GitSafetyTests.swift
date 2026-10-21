import XCTest
import GitKit
@testable import SuperMenuGit

final class GitSafetyTests: XCTestCase {
    func testResetModesHaveDifferentIndexAndWorktreeEffects() async throws {
        for mode in HistoryReset.allCases {
            let repo = try Fixture()
            defer { repo.remove() }
            let first = try repo.commit("one", content: "1")
            _ = try repo.commit("two", content: "2")
            let workspace = try await GitWorkspace.open(at: repo.url)
            var plan = try await workspace.preview(.reset, selected: [first])
            plan.resetMode = mode
            try await workspace.execute(plan)
            XCTAssertEqual(try repo.git(["rev-parse", "HEAD"]), first)
            XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), mode == .hard ? "1" : "2")
            XCTAssertEqual(try repo.git(["show", ":file.txt"]), mode == .soft ? "2" : "1")
        }
    }

    func testRevertConflictCanBeAbortedAfterReopening() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("one", content: "1")
        let second = try repo.commit("two", content: "2")
        let head = try repo.commit("three", content: "3")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.revert, selected: [second])
        do { try await workspace.execute(plan); XCTFail("Expected conflict") } catch {}
        let reopened = try await GitWorkspace.open(at: repo.url)
        let operation = try await reopened.operation()
        XCTAssertEqual(operation, .revert)
        let conflicts = try await reopened.conflicts()
        XCTAssertEqual(conflicts, ["file.txt"])
        try await reopened.finishOperation(abort: true)
        XCTAssertEqual(try repo.git(["rev-parse", "HEAD"]), head)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "3")
        XCTAssertEqual(try repo.git(["status", "--porcelain"]), "")
    }

    func testRevertConflictResolutionCanContinue() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("one", content: "1")
        let second = try repo.commit("two", content: "2")
        _ = try repo.commit("three", content: "3")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.revert, selected: [second])
        do { try await workspace.execute(plan); XCTFail("Expected conflict") } catch {}
        try "resolved".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try await workspace.markResolved(path: "file.txt")
        try await workspace.finishOperation(abort: false)
        XCTAssertEqual(try repo.git(["rev-list", "--count", "HEAD"]), "4")
        let operation = try await workspace.operation()
        XCTAssertNil(operation)
    }

    func testRebaseReordersRenamesAndCombines() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "1", file: "a")
        _ = try repo.commit("two", content: "2", file: "b")
        _ = try repo.commit("three", content: "3", file: "c")
        let tree = try repo.git(["rev-parse", "HEAD^{tree}"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        var plan = try await workspace.preview(.rebase, selected: [first])
        plan.entries.swapAt(0, 1)
        plan.entries[0].message = "Renamed"
        plan.entries[0].action = .reword
        plan.entries[2].action = .squash
        try await workspace.execute(plan)
        XCTAssertEqual(try repo.git(["rev-parse", "HEAD^{tree}"]), tree)
        XCTAssertEqual(try repo.git(["log", "--format=%s", "--reverse"]), "Renamed\none")
        XCTAssertEqual(try repo.git(["log", "-1", "--format=%B"]), "one\n\nthree")
    }

    func testRebaseConflictCanContinueAfterReopening() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "1")
        _ = try repo.commit("two", content: "2")
        _ = try repo.commit("three", content: "3", file: "other")
        let workspace = try await GitWorkspace.open(at: repo.url)
        var plan = try await workspace.preview(.rebase, selected: [first])
        plan.entries.swapAt(0, 1)
        plan.entries[0].message = "Reordered"
        plan.entries[0].action = .reword
        do { try await workspace.execute(plan); XCTFail("Expected conflict") } catch {}
        let reopened = try await GitWorkspace.open(at: repo.url)
        let operation = try await reopened.operation()
        XCTAssertEqual(operation, .rebase)
        try "resolved".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try await reopened.markResolved(path: "file.txt")
        // Replaying the original root may conflict again; abort remains available.
        do { try await reopened.finishOperation(abort: false) } catch {}
        XCTAssertEqual(try repo.git(["log", "-1", "--format=%s"]), "Reordered")
        let following = try await reopened.operation()
        if following != nil { try await reopened.finishOperation(abort: true) }
        let final = try await reopened.operation()
        XCTAssertNil(final)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent(".git/supermenu-replay").path))
    }

    func testMultipleRevertsUndoNewestFirstAndRetainHistory() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("one", content: "1")
        let second = try repo.commit("two", content: "2")
        let third = try repo.commit("three", content: "3")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.revert, selected: [second, third])
        XCTAssertEqual(plan.affected.map(\.id), [third, second])
        try await workspace.execute(plan)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "1")
        XCTAssertEqual(try repo.git(["rev-list", "--count", "HEAD"]), "5")
    }

    func testRejectsNoncontiguousAndDirtySelections() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "1")
        _ = try repo.commit("two", content: "2")
        let third = try repo.commit("three", content: "3")
        let workspace = try await GitWorkspace.open(at: repo.url)
        do { _ = try await workspace.preview(.squash, selected: [first, third]); XCTFail("Noncontiguous") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.contiguous") }
        let preview = try await workspace.preview(.revert, selected: [third])
        try "dirty".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        do { try await workspace.execute(preview); XCTFail("Stale worktree") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.stale") }
        do { _ = try await workspace.preview(.reset, selected: [first]); XCTFail("Dirty") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.dirty") }
    }

    func testEmptyRepositoryAndNestedWorktreeDiscovery() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let empty = try await GitWorkspace.open(at: repo.url)
        let snapshot = try await empty.snapshot()
        XCTAssertTrue(snapshot.head.isEmpty)
        let history = try await empty.history()
        XCTAssertTrue(history.commits.isEmpty)
        _ = try repo.commit("one", content: "1")
        let worktree = repo.url.appendingPathComponent("linked")
        try repo.git(["worktree", "add", "-b", "feature", worktree.path])
        let child = worktree.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let workspace = try await GitWorkspace.open(at: child)
        XCTAssertEqual(workspace.root.resolvingSymlinksInPath(), worktree.resolvingSymlinksInPath())
    }

    func testGraphIncludesMergeEdgesAndRemoteReachability() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "side"])
        _ = try repo.commit("side", content: "side", file: "side")
        try repo.git(["checkout", "main"])
        _ = try repo.commit("main", content: "main", file: "main")
        try repo.git(["merge", "--no-ff", "side", "-m", "merge"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let page = try await workspace.history()
        let graph = GraphLayout.layout(page.commits)
        XCTAssertGreaterThan(graph.width, 1)
        XCTAssertEqual(graph.nodes[0].outgoing.count, 2)
        let head = try repo.git(["rev-parse", "HEAD"])
        do { _ = try await workspace.preview(.rebase, selected: [head]); XCTFail("Must not flatten merge") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.merge") }
        let next = try repo.commit("next", content: "next")
        try repo.git(["update-ref", "refs/remotes/origin/main", next])
        let plan = try await workspace.preview(.rebase, selected: [next])
        XCTAssertEqual(plan.published, [next])
    }
}
