import XCTest
import GitKit
@testable import SuperMenuGit

final class GitCherryPickTests: XCTestCase {
    func testDependenciesUseTopologyDespiteReversedDatesAndPreviewIsReadOnly() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let base = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "source"])
        let first = try repo.commit("first", content: "first")
        let second = try repo.commit("second", content: "second")
        // Force the descendant to have an older timestamp than its parent.
        try repo.git(["-c", "alias.old=!GIT_COMMITTER_DATE=2001-01-01T00:00:00Z git commit --amend --no-edit --date=2001-01-01T00:00:00Z", "old"])
        let tip = try repo.git(["rev-parse", "HEAD"])
        XCTAssertNotEqual(second, tip)
        try repo.git(["checkout", "main"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let before = try await workspace.snapshot()
        let plan = try await workspace.preview(.cherryPick, selected: [tip, first])
        XCTAssertEqual(plan.entries.map(\.id), [first, tip])
        XCTAssertEqual(plan.snapshot.branch, "main")
        XCTAssertEqual(plan.comparisons.map(\.to), [first, tip])
        let command = try await workspace.commandPreview(for: plan)
        XCTAssertEqual(command.arguments, ["cherry-pick", "--no-edit", "--no-walk=unsorted", first, tip])
        let afterPreview = try await workspace.snapshot()
        XCTAssertEqual(before, afterPreview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent(".git/sequencer").path))
        try await workspace.execute(plan)
        XCTAssertEqual(try repo.git(["log", "--format=%s", "--reverse", base + "..HEAD"]), "first\nsecond")
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "second")
        XCTAssertEqual(try repo.git(["rev-parse", "source"]), tip)
        let records = await workspace.operationRecords()
        XCTAssertEqual(records.last?.status, .succeeded)
        XCTAssertEqual(records.last?.exitCode, 0)
        XCTAssertTrue(records.last?.command?.hasSuffix(first + " " + tip) == true)
    }

    func testExplicitOrderIsExecutedAndInvalidEditedSelectionsNeverStart() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "source"])
        let first = try repo.commit("first", content: "one", file: "one")
        let second = try repo.commit("second", content: "two", file: "two")
        try repo.git(["checkout", "main"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let original = try await workspace.preview(.cherryPick, selected: [first, second])
        for invalid in 0...2 {
            var plan = original
            if invalid == 0 { plan.entries.removeLast() }
            if invalid == 1 { plan.entries[1] = plan.entries[0] }
            if invalid == 2 { plan.entries[0].action = .squash }
            do { try await workspace.execute(plan); XCTFail("Invalid sequence must not execute") }
            catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.cherryPickOrder") }
        }
        let after = try await workspace.snapshot()
        XCTAssertEqual(after, original.snapshot)
        let records = await workspace.operationRecords()
        XCTAssertTrue(records.allSatisfy { $0.status == .notStarted && $0.command == nil })
        var reordered = original
        reordered.entries.reverse()
        let command = try await workspace.commandPreview(for: reordered)
        XCTAssertEqual(Array(command.arguments.suffix(2)), [second, first])
        try await workspace.execute(reordered)
        XCTAssertEqual(try repo.git(["log", "-2", "--format=%s", "--reverse"]), "second\nfirst")
    }

    func testConflictReopenResolveContinueAndSourceBranchUnchanged() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "source"])
        let picked = try repo.commit("source edit", content: "source")
        let next = try repo.commit("after conflict", content: "next", file: "next")
        try repo.git(["checkout", "main"])
        _ = try repo.commit("target edit", content: "target")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.cherryPick, selected: [picked, next])
        do { try await workspace.execute(plan); XCTFail("Expected conflict") } catch {}
        let reopened = try await GitWorkspace.open(at: repo.url)
        let operation = try await reopened.operation()
        XCTAssertEqual(operation, .cherryPick)
        let canSkip = try await reopened.canSkipEmptyCherryPick()
        XCTAssertFalse(canSkip)
        do { try await reopened.finishOperation(abort: false); XCTFail("Unresolved conflict") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.conflicts") }
        try "resolved".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try await reopened.markResolved(path: "file.txt")
        try await reopened.finishOperation(abort: false)
        let finished = try await reopened.operation()
        XCTAssertNil(finished)
        XCTAssertEqual(try repo.git(["log", "-2", "--format=%s", "--reverse"]), "source edit\nafter conflict")
        XCTAssertEqual(try repo.git(["rev-parse", "source"]), next)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "resolved")
    }

    func testAbortRestoresTargetBeforeWholeSequenceIncludingSuccessfulPicks() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "source"])
        let first = try repo.commit("clean", content: "clean", file: "other")
        let second = try repo.commit("conflicting", content: "source")
        try repo.git(["checkout", "main"])
        let target = try repo.commit("target", content: "target")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.cherryPick, selected: [first, second])
        do { try await workspace.execute(plan); XCTFail("Expected conflict") } catch {}
        XCTAssertNotEqual(try repo.git(["rev-parse", "HEAD"]), target)
        let reopened = try await GitWorkspace.open(at: repo.url)
        try await reopened.finishOperation(abort: true)
        XCTAssertEqual(try repo.git(["rev-parse", "HEAD"]), target)
        XCTAssertEqual(try repo.git(["status", "--porcelain"]), "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("other").path))
    }

    func testEmptyAndAlreadyAppliedPicksPauseUntilExplicitSkip() async throws {
        for empty in [true, false] {
            let repo = try Fixture()
            defer { repo.remove() }
            _ = try repo.commit("base", content: "base")
            try repo.git(["checkout", "-b", "source"])
            if empty { try repo.git(["commit", "--allow-empty", "-m", "empty"]) }
            else { _ = try repo.commit("duplicate patch", content: "same", file: "same") }
            let first = try repo.git(["rev-parse", "HEAD"])
            let second = try repo.commit("next", content: "next", file: "next")
            try repo.git(["checkout", "main"])
            if !empty { _ = try repo.commit("already applied", content: "same", file: "same") }
            let head = try repo.git(["rev-parse", "HEAD"])
            let workspace = try await GitWorkspace.open(at: repo.url)
            let plan = try await workspace.preview(.cherryPick, selected: [first, second])
            do { try await workspace.execute(plan); XCTFail("Empty pick must pause") } catch {}
            XCTAssertEqual(try repo.git(["rev-parse", "HEAD"]), head)
            let records = await workspace.operationRecords()
            XCTAssertEqual(records.last?.status, .interrupted)
            let reopened = try await GitWorkspace.open(at: repo.url)
            let canSkip = try await reopened.canSkipEmptyCherryPick()
            XCTAssertTrue(canSkip)
            // Never discard an edit made since the UI offered Skip.
            try "unrelated".write(to: repo.url.appendingPathComponent("untracked"), atomically: true, encoding: .utf8)
            do { try await reopened.skipEmptyCherryPick(); XCTFail("Dirty skip") }
            catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.skipCherryPick") }
            try FileManager.default.removeItem(at: repo.url.appendingPathComponent("untracked"))
            try await reopened.skipEmptyCherryPick()
            XCTAssertEqual(try repo.git(["log", "-1", "--format=%s"]), "next")
            XCTAssertEqual(try repo.git(["rev-list", "--count", head + "..HEAD"]), "1")
            let operation = try await reopened.operation()
            XCTAssertNil(operation)
            let skipLog = await reopened.operationRecords()
            XCTAssertTrue(skipLog.last?.command?.hasSuffix("cherry-pick --skip") == true)
        }
    }

    func testSingleDuplicateCanBeAbortedAndRootCommitCanBePicked() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let root = try repo.commit("root", content: "root")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let duplicate = try await workspace.preview(.cherryPick, selected: [root])
        do { try await workspace.execute(duplicate); XCTFail("Duplicate must pause") } catch {}
        try await workspace.finishOperation(abort: true)
        XCTAssertEqual(try repo.git(["rev-parse", "HEAD"]), root)
        try repo.git(["checkout", "--orphan", "unrelated"])
        try repo.git(["rm", "-f", "file.txt"])
        _ = try repo.commit("other root", content: "other", file: "other")
        let plan = try await workspace.preview(.cherryPick, selected: [root])
        XCTAssertNil(plan.comparisons.first?.from)
        try await workspace.execute(plan)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "root")
        XCTAssertEqual(try repo.git(["rev-parse", "main"]), root)
    }

    func testDirtyDetachedMergeAndStalePlansAreRejected() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let base = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "source"])
        let side = try repo.commit("side", content: "side", file: "side")
        try repo.git(["checkout", "main"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.cherryPick, selected: [side])
        try "dirty".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        do { _ = try await workspace.preview(.cherryPick, selected: [side]); XCTFail("Dirty preview") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.dirty") }
        do { try await workspace.execute(plan); XCTFail("Stale plan") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.stale") }
        try repo.git(["restore", "file.txt"])
        try repo.git(["checkout", "--detach", base])
        do { _ = try await workspace.preview(.cherryPick, selected: [side]); XCTFail("Detached") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.detached") }
        try repo.git(["checkout", "source"])
        do { try await workspace.execute(plan); XCTFail("Changed branch") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.stale") }
        try repo.git(["checkout", "main"])
        try repo.git(["merge", "--no-ff", "source", "-m", "merge"])
        let merge = try repo.git(["rev-parse", "HEAD"])
        do { _ = try await workspace.preview(.cherryPick, selected: [merge]); XCTFail("Mainline required") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.cherryPickMerge") }
    }

    func testManuallyCommittedConflictStillRecognizesPendingSequence() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "source"])
        let conflict = try repo.commit("conflict", content: "source")
        let next = try repo.commit("next", content: "next", file: "next")
        try repo.git(["checkout", "main"])
        _ = try repo.commit("target", content: "target")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.cherryPick, selected: [conflict, next])
        do { try await workspace.execute(plan); XCTFail("Expected conflict") } catch {}
        // A user may resolve and commit from their editor, removing the HEAD
        // marker while Git still has a sequence to finish.
        _ = try repo.commit("manual resolution", content: "resolved")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent(".git/CHERRY_PICK_HEAD").path))
        let reopened = try await GitWorkspace.open(at: repo.url)
        let operation = try await reopened.operation()
        XCTAssertEqual(operation, .cherryPick)
        let skip = try await reopened.canSkipEmptyCherryPick()
        XCTAssertFalse(skip, "Do not skip the next pick after a manual commit")
        do { _ = try await reopened.preview(.cherryPick, selected: [next]); XCTFail("Pending sequence") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.inProgress") }
        try await reopened.finishOperation(abort: false)
        XCTAssertEqual(try repo.git(["log", "-1", "--format=%s"]), "next")
        let completed = try await reopened.operation()
        XCTAssertNil(completed)
    }

    func testOmittedIntermediateCommitDoesNotInvertSelectedAncestors() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("base", content: "base")
        try repo.git(["checkout", "-b", "source"])
        let first = try repo.commit("first", content: "first", file: "first")
        _ = try repo.commit("omitted", content: "omitted", file: "omitted")
        let last = try repo.commit("last", content: "last", file: "last")
        try repo.git(["checkout", "main"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.cherryPick, selected: [last, first])
        XCTAssertEqual(plan.entries.map(\.id), [first, last])
        try await workspace.execute(plan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("omitted").path))
    }

    func testLargeRepositoryAllowsNearbyPicksButRejectsOversizedSelectedRange() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        var stream = ""
        for index in 0..<10_001 {
            let message = "Synthetic \(index)"
            stream += "commit refs/heads/main\ncommitter Example <example@example.invalid> 1700000000 +0000\ndata \(message.utf8.count)\n\(message)\n\n"
        }
        let input = repo.url.appendingPathComponent(".git/import-input")
        try stream.write(to: input, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = repo.url
        process.arguments = ["fast-import", "--quiet"]
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        process.standardInput = handle
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let ids = try repo.git(["rev-list", "--max-count=2", "HEAD"]).split(separator: "\n").map(String.init)
        let workspace = try await GitWorkspace.open(at: repo.url)
        let before = try await workspace.snapshot()
        let nearby = try await workspace.preview(.cherryPick, selected: Set(ids))
        XCTAssertEqual(nearby.entries.map(\.id), ids.reversed())
        let oldest = try repo.git(["rev-list", "--max-parents=0", "HEAD"])
        do { _ = try await workspace.preview(.cherryPick, selected: [ids[0], oldest]); XCTFail("Partial ancestry") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.rangeTooLarge") }
        let after = try await workspace.snapshot()
        XCTAssertEqual(before, after)
        // One commit needs no ordering walk, even in a large repository.
        let single = try await workspace.preview(.cherryPick, selected: [ids[0]])
        XCTAssertEqual(single.entries.map(\.id), [ids[0]])
    }

    func testCommonAncestorSelectionAndUnrelatedHistoriesRemainComplete() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let root = try repo.commit("root", content: "root")
        try repo.git(["checkout", "-b", "left"])
        let left = try repo.commit("left", content: "left", file: "left")
        try repo.git(["checkout", "main"])
        try repo.git(["checkout", "-b", "right"])
        let right = try repo.commit("right", content: "right", file: "right")
        try repo.git(["checkout", "main"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.cherryPick, selected: [root, left, right])
        XCTAssertEqual(plan.entries.first?.id, root)
        XCTAssertEqual(Set(plan.entries.map(\.id)), [root, left, right])
        let branches = try await workspace.preview(.cherryPick, selected: [left, right])
        try await workspace.execute(branches)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("left").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("right").path))
        try repo.git(["checkout", "--orphan", "unrelated"])
        try repo.git(["rm", "-rf", "."])
        let unrelated = try repo.commit("unrelated", content: "unrelated", file: "unrelated")
        let separate = try await workspace.preview(.cherryPick, selected: [root, unrelated])
        XCTAssertEqual(Set(separate.entries.map(\.id)), [root, unrelated])
    }
}
