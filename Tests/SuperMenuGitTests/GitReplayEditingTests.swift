import XCTest
@testable import SuperMenuGit

final class GitReplayEditingTests: XCTestCase {
    func testStandaloneActionsRejectUnsafeRepositoryStates() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let root = try repo.commit("root", content: "root", file: "root")
        let tip = try repo.commit("tip", content: "tip", file: "tip")
        let workspace = try await GitWorkspace.open(at: repo.url)
        do { _ = try await workspace.preview(.reword, selected: [root, tip]); XCTFail("Reword needs one target") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.selectOne") }
        for action in [HistoryAction.reword, .drop] {
            let plan = try await workspace.preview(action, selected: [root])
            let pending = repo.url.appendingPathComponent("pending")
            try "pending".write(to: pending, atomically: true, encoding: .utf8)
            do { _ = try await workspace.preview(action, selected: [root]); XCTFail("Dirty worktree") }
            catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.dirty") }
            do { try await workspace.execute(plan); XCTFail("Stale snapshot") }
            catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.stale") }
            try FileManager.default.removeItem(at: pending)
            try repo.git(["checkout", "--detach", tip])
            do { _ = try await workspace.preview(action, selected: [root]); XCTFail("Detached HEAD") }
            catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.detached") }
            try repo.git(["checkout", "main"])
        }
        try repo.git(["checkout", "-b", "side", root])
        let side = try repo.commit("side", content: "side", file: "side")
        try repo.git(["checkout", "main"])
        for action in [HistoryAction.reword, .drop] {
            do { _ = try await workspace.preview(action, selected: [side]); XCTFail("Not on current mainline") }
            catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.ancestry") }
        }
        try repo.git(["merge", "--no-ff", "side", "-m", "merge"])
        let merged = try repo.git(["rev-parse", "HEAD"])
        for action in [HistoryAction.reword, .drop] {
            do { _ = try await workspace.preview(action, selected: [root]); XCTFail("Affected merge") }
            catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.merge") }
        }
        XCTAssertEqual(try repo.git(["rev-parse", "HEAD"]), merged)
        XCTAssertEqual(try repo.git(["status", "--porcelain"]), "")
    }

    func testDropBetweenCombinedCommitsDoesNotBreakMessageGroup() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "one", file: "one")
        _ = try repo.commit("two", content: "two", file: "two")
        _ = try repo.commit("three", content: "three", file: "three")
        let workspace = try await GitWorkspace.open(at: repo.url)
        var plan = try await workspace.preview(.rebase, selected: [first])
        plan.entries[1].action = .drop
        plan.entries[2].action = .squash
        try await workspace.execute(plan)
        XCTAssertEqual(try repo.git(["log", "--format=%B"]), "one\n\nthree")
        XCTAssertEqual(try repo.git(["rev-list", "--count", "HEAD"]), "1")
        XCTAssertEqual(try repo.git(["ls-tree", "--name-only", "HEAD"]), "one\nthree")
    }

    func testRewordPreservesTreeAndOtherRefsWhileRewritingDescendants() async throws {
        for rootSelection in [true, false] {
            let repo = try Fixture()
            defer { repo.remove() }
            let root = try repo.commit("root", content: "root", file: "root")
            let middle = try repo.commit("middle", content: "middle", file: "middle")
            let tip = try repo.commit("tip", content: "tip", file: "tip")
            let tree = try repo.git(["rev-parse", "HEAD^{tree}"])
            try repo.git(["branch", "preserved", tip])
            let workspace = try await GitWorkspace.open(at: repo.url)
            var plan = try await workspace.preview(.reword, selected: [rootSelection ? root : middle])
            XCTAssertEqual(plan.entries.first?.action, .reword)
            XCTAssertEqual(plan.entries.last?.action, .pick)
            plan.entries[0].message = "New 'message'\n\n$(touch unintended)"
            let before = try await workspace.snapshot()
            let preview = try await workspace.commandPreview(for: plan)
            XCTAssertTrue(preview.files.contains { $0.content == plan.entries[0].message })
            let after = try await workspace.snapshot()
            XCTAssertEqual(before, after)
            try await workspace.execute(plan)
            XCTAssertEqual(try repo.git(["rev-parse", "HEAD^{tree}"]), tree)
            XCTAssertEqual(try repo.git(["rev-parse", "preserved"]), tip)
            XCTAssertNotEqual(try repo.git(["rev-parse", "HEAD"]), tip)
            let revised = try repo.git(["log", "--format=%B", "-1", rootSelection ? "HEAD~2" : "HEAD~1"])
            XCTAssertEqual(revised, plan.entries[0].message)
            XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("unintended").path))
        }
    }

    func testSquashIncludesMessageWhileFixupDiscardsIt() async throws {
        for combine in [ReplayAction.squash, .fixup] {
            let repo = try Fixture()
            defer { repo.remove() }
            let first = try repo.commit("one", content: "1", file: "one")
            _ = try repo.commit("two", content: "2", file: "two")
            _ = try repo.commit("three", content: "3", file: "three")
            let tree = try repo.git(["rev-parse", "HEAD^{tree}"])
            let workspace = try await GitWorkspace.open(at: repo.url)
            var plan = try await workspace.preview(.rebase, selected: [first])
            plan.entries[0].action = .reword
            plan.entries[0].message = "renamed"
            plan.entries[1].action = combine
            plan.entries[1].message = "edited second"
            plan.entries[2].action = .fixup
            plan.entries[2].message = "must not appear"
            try await workspace.execute(plan)
            XCTAssertEqual(try repo.git(["rev-parse", "HEAD^{tree}"]), tree)
            XCTAssertEqual(try repo.git(["rev-list", "--count", "HEAD"]), "1")
            XCTAssertEqual(try repo.git(["log", "-1", "--format=%B"]), combine == .squash ? "renamed\n\nedited second" : "renamed")
        }
    }

    func testDropMiddleRootAndEntireNonRootTail() async throws {
        for mode in 0...2 {
            let repo = try Fixture()
            defer { repo.remove() }
            let first = try repo.commit("one", content: "1", file: "one")
            let second = try repo.commit("two", content: "2", file: "two")
            let third = try repo.commit("three", content: "3", file: "three")
            let workspace = try await GitWorkspace.open(at: repo.url)
            let selected: Set<String> = mode == 0 ? [second] : (mode == 1 ? [first] : [second, third])
            let plan = try await workspace.preview(.drop, selected: selected)
            XCTAssertEqual(Set(plan.entries.filter { $0.action == .drop }.map(\.id)), selected)
            let preview = try await workspace.commandPreview(for: plan)
            let todo = try XCTUnwrap(preview.files.first { $0.name == "todo" }?.content)
            for id in selected { XCTAssertTrue(todo.contains("drop " + id + "\n")) }
            try await workspace.execute(plan)
            let expected = mode == 0 ? "one\nthree" : (mode == 1 ? "two\nthree" : "one")
            XCTAssertEqual(try repo.git(["ls-tree", "--name-only", "HEAD"]), expected.split(separator: "\n").sorted().joined(separator: "\n"))
            XCTAssertEqual(try repo.git(["log", "--reverse", "--format=%s"]), expected)
            if mode == 2 { XCTAssertEqual(try repo.git(["rev-parse", "HEAD"]), first) }
        }
    }

    func testInvalidActionsAndWholeHistoryDropNeverWrite() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "1", file: "one")
        let second = try repo.commit("two", content: "2", file: "two")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let original = try await workspace.preview(.rebase, selected: [first])
        for actions in [[ReplayAction.squash, .pick], [.drop, .fixup], [.drop, .drop]] {
            var plan = original
            for i in actions.indices { plan.entries[i].action = actions[i] }
            let key = actions == [.drop, .drop] ? "git.error.dropAllHistory" : "git.error.replay"
            XCTAssertEqual(plan.replayValidationError, key)
            do { _ = try await workspace.commandPreview(for: plan); XCTFail("Invalid preview") }
            catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, key) }
            do { try await workspace.execute(plan); XCTFail("Invalid execution") }
            catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, key) }
        }
        do { _ = try await workspace.preview(.drop, selected: [first, second]); XCTFail("Cannot erase all history") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.dropAllHistory") }
        let after = try await workspace.snapshot()
        XCTAssertEqual(original.snapshot, after)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent(".git/supermenu-replay").path))
    }

    func testDroppingDependencyCanAbortOrResolveAndContinueAfterReopen() async throws {
        for abort in [true, false] {
            let repo = try Fixture()
            defer { repo.remove() }
            _ = try repo.commit("base", content: "1")
            let dropped = try repo.commit("drop this", content: "2")
            let tip = try repo.commit("depends on dropped", content: "3")
            let workspace = try await GitWorkspace.open(at: repo.url)
            var plan = try await workspace.preview(.drop, selected: [dropped])
            plan.entries[1].action = .reword
            plan.entries[1].message = "kept after resolution"
            do { try await workspace.execute(plan); XCTFail("Expected dependency conflict") } catch {}
            let reopened = try await GitWorkspace.open(at: repo.url)
            let operation = try await reopened.operation()
            XCTAssertEqual(operation, .rebase)
            if !abort {
                try "resolved".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
                try await reopened.markResolved(path: "file.txt")
            }
            try await reopened.finishOperation(abort: abort)
            XCTAssertEqual(try repo.git(["log", "-1", "--format=%s"]), abort ? "depends on dropped" : "kept after resolution")
            XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), abort ? "3" : "resolved")
            if abort { XCTAssertEqual(try repo.git(["rev-parse", "HEAD"]), tip) }
            let finished = try await reopened.operation()
            XCTAssertNil(finished)
            XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent(".git/supermenu-replay").path))
        }
    }

    func testRewordEmptyCommitPreservesEmptyCommit() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("base", content: "base")
        try repo.git(["commit", "--allow-empty", "-m", "empty"])
        let empty = try repo.git(["rev-parse", "HEAD"])
        let tree = try repo.git(["rev-parse", "HEAD^{tree}"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        var plan = try await workspace.preview(.reword, selected: [empty])
        plan.entries[0].message = "renamed empty"
        try await workspace.execute(plan)
        XCTAssertEqual(try repo.git(["rev-list", "--count", "HEAD"]), "2")
        XCTAssertEqual(try repo.git(["rev-parse", "HEAD^{tree}"]), tree)
        XCTAssertEqual(try repo.git(["log", "-1", "--format=%s"]), "renamed empty")
    }

    func testFixupPreservesAnOriginallyEmptyMessage() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        // Avoid matching Git's synthetic empty root object (same identity,
        // timestamp, empty tree and message) during a same-second --root rebase.
        try repo.git(["commit", "--date=2001-01-01T00:00:00Z", "--allow-empty", "--allow-empty-message", "-m", ""])
        let root = try repo.git(["rev-parse", "HEAD"])
        _ = try repo.commit("discard this message", content: "change")
        let tree = try repo.git(["rev-parse", "HEAD^{tree}"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        var plan = try await workspace.preview(.rebase, selected: [root])
        plan.entries[1].action = .fixup
        do { try await workspace.execute(plan) }
        catch {
            let records = await workspace.operationRecords()
            XCTFail("Empty-message replay failed: " + (records.last?.stderr ?? "no Git output"))
            return
        }
        XCTAssertEqual(try repo.git(["log", "-1", "--format=%B"]), "")
        XCTAssertEqual(try repo.git(["rev-list", "--count", "HEAD"]), "1")
        XCTAssertEqual(try repo.git(["rev-parse", "HEAD^{tree}"]), tree)
    }

    func testReorderedFirstFixupIsRejectedAndDroppedMessagesAreIgnored() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "1", file: "one")
        _ = try repo.commit("two", content: "2", file: "two")
        _ = try repo.commit("three", content: "3", file: "three")
        let workspace = try await GitWorkspace.open(at: repo.url)
        var plan = try await workspace.preview(.rebase, selected: [first])
        plan.entries[1].action = .fixup
        plan.entries.swapAt(0, 1)
        XCTAssertEqual(plan.replayValidationError, "git.error.replay")
        plan.entries.swapAt(0, 1)
        plan.entries[1].message = ""
        plan.entries[2].action = .drop
        plan.entries[2].message = ""
        plan.entries[0].message = "ignored draft for pick"
        XCTAssertNil(plan.replayValidationError)
        try await workspace.execute(plan)
        XCTAssertEqual(try repo.git(["log", "-1", "--format=%B"]), "one")
        XCTAssertEqual(try repo.git(["ls-tree", "--name-only", "HEAD"]), "one\ntwo")
    }
}
