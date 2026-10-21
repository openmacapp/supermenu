import XCTest
@testable import SuperMenuGit

final class GitOperationRecordTests: XCTestCase {
    func testSuccessRejectedPlanAndClearingAreRecordedWithoutPersistingLogs() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "1")
        _ = try repo.commit("two", content: "2")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.reset, selected: [first])
        try await workspace.execute(plan)
        do { try await workspace.execute(plan); XCTFail("Stale plans must be rejected") } catch {}
        let records = await workspace.operationRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].status, .succeeded)
        XCTAssertEqual(records[0].exitCode, 0)
        XCTAssertTrue(records[0].command?.contains("reset --soft " + first) == true)
        XCTAssertFalse(records[0].commandModified)
        XCTAssertEqual(records[1].status, .notStarted)
        XCTAssertNil(records[1].exitCode)
        XCTAssertNil(records[1].command)
        XCTAssertEqual(records[1].failureKey, "git.error.stale")
        let before = try await workspace.snapshot()
        await workspace.clearOperationRecords()
        let empty = await workspace.operationRecords()
        let after = try await workspace.snapshot()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(before, after)
        let reopened = try await GitWorkspace.open(at: repo.url)
        let reopenedRecords = await reopened.operationRecords()
        XCTAssertTrue(reopenedRecords.isEmpty)
    }

    func testConflictContinueAndAbortShowActualParentCommands() async throws {
        for abort in [false, true] {
            let repo = try Fixture()
            defer { repo.remove() }
            _ = try repo.commit("one", content: "1")
            let second = try repo.commit("two", content: "2")
            _ = try repo.commit("three", content: "3")
            let workspace = try await GitWorkspace.open(at: repo.url)
            let plan = try await workspace.preview(.revert, selected: [second])
            do { try await workspace.execute(plan); XCTFail("Expected conflict") } catch {}
            let paused = await workspace.operationRecords()
            XCTAssertEqual(paused.last?.status, .interrupted)
            XCTAssertNotEqual(paused.last?.exitCode, 0)
            XCTAssertTrue(paused.last?.command?.contains("revert --no-edit " + second) == true)
            if !abort {
                try "resolved".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
                try await workspace.markResolved(path: "file.txt")
            }
            try await workspace.finishOperation(abort: abort)
            let records = await workspace.operationRecords()
            XCTAssertEqual(records.count, abort ? 2 : 3)
            XCTAssertEqual(records.last?.status, .succeeded)
            XCTAssertTrue(records.last?.command?.hasSuffix(abort ? "revert --abort" : "revert --continue") == true)
            if !abort { XCTAssertTrue(records[1].command?.hasSuffix("add -- file.txt") == true) }
        }
    }

    func testOversizedOutputIsDrainedWithoutStoppingTheMutation() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let script = repo.url.appendingPathComponent("noisy.sh")
        try "#!/bin/sh\n/usr/bin/awk 'BEGIN { for (i=0;i<100000;i++) print \"synthetic standard output\" }'\n/usr/bin/awk 'BEGIN { for (i=0;i<100000;i++) print \"synthetic error output\" }' >&2\nprintf done > completed\nexit 7\n".write(to: script, atomically: true, encoding: .utf8)
        let result = await BoundedGitMutation.run(root: repo.url, arguments: ["-c", "alias.noisy=!sh noisy.sh", "noisy"])
        XCTAssertTrue(result.started)
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertTrue(result.stdoutTruncated && result.stderrTruncated)
        XCTAssertLessThanOrEqual(result.stdout.count + result.stderr.count, 64 * 1024)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("completed")), "done")
    }

    func testLaunchFailureAndTaskCancellationHaveHonestResults() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        for _ in 0..<5 {
            let result = await BoundedGitMutation.run(root: repo.url, arguments: [], executable: repo.url.appendingPathComponent("missing-git"))
            XCTAssertFalse(result.started)
            XCTAssertNil(result.exitCode)
        }
        let script = repo.url.appendingPathComponent("slow.sh")
        try "#!/bin/sh\nsleep 0.2\nprintf complete > completed\n".write(to: script, atomically: true, encoding: .utf8)
        let task = Task { await BoundedGitMutation.run(root: repo.url, arguments: ["-c", "alias.slow=!sh slow.sh", "slow"]) }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result.exitCode, 0, "UI task cancellation must not stop a Git mutation")
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("completed")), "complete")
    }

    func testFailedCommandKeepsExitCodeAndOnlySanitizedDisplayOutput() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let workspace = try await GitWorkspace.open(at: repo.url)
        let script = repo.url.appendingPathComponent("failure.sh")
        try "#!/bin/sh\nprintf 'password=synthetic-value\\n' >&2\nprintf '%s\\n' \"$PWD\"\nexit 42\n".write(
            to: script, atomically: true, encoding: .utf8)
        do {
            try await workspace.recordOperation(action: "reset") { record in
                try await workspace.runMutation(["-c", "alias.failure=!sh failure.sh", "failure"], record: &record)
            }
            XCTFail("Expected a command failure")
        } catch let error as WorkspaceFailure { XCTAssertEqual(error.key, "git.log.commandFailed") }
        let records = await workspace.operationRecords()
        let record = try XCTUnwrap(records.last)
        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.exitCode, 42)
        XCTAssertFalse(record.stderr.contains("synthetic-value"))
        XCTAssertFalse(record.stdout.contains(repo.url.path))
        XCTAssertFalse(record.stdout.contains(repo.url.resolvingSymlinksInPath().path))
    }

    func testRecordsEvictByBytesAndCountAndClear() {
        var store = GitOperationStore()
        for _ in 0..<110 { store.append(GitOperationRecord(action: "reset")) }
        XCTAssertEqual(store.records.count, 100)
        let firstID = store.records[0].id
        for _ in 0..<40 {
            var record = GitOperationRecord(action: "rebase")
            record.stdout = String(repeating: "x", count: 64 * 1024)
            store.append(record)
        }
        XCTAssertFalse(store.records.contains { $0.id == firstID })
        XCTAssertLessThanOrEqual(store.cost, 2 * 1024 * 1024)
        XCTAssertLessThan(store.records.count, 40)
        store.clear()
        XCTAssertEqual(store.cost, 0)
        XCTAssertTrue(store.records.isEmpty)
    }

    func testDiagnosticRedactionUsesOnlySyntheticValues() {
        let root = URL(fileURLWithPath: "/example-workspace/project")
        let identity = "Example Author <person@example.invalid>"
        let token = "ghp_" + String(repeating: "A", count: 30)
        let home = "/" + ["Users", "synthetic-person", "workspace"].joined(separator: "/")
        let credentialURL = ["https://", "example:secret@", "example.invalid/repo?token=hidden"].joined()
        let input = "\(identity)\n\(root.path)/file\n\(home)/file\n\(credentialURL)\n\(token)\npassword=hidden\n\u{1b}[31mcolored\u{1b}[0m\rspoof\u{202e}text"
        let output = GitLogRedactor.redact(input, root: root)
        for secret in ["person@", "synthetic-person", "example-workspace", "secret", "hidden", token] {
            XCTAssertFalse(output.contains(secret))
        }
        XCTAssertFalse(output.contains("\u{1b}"))
        XCTAssertFalse(output.contains("\u{202e}"))
        XCTAssertFalse(output.contains("\r"))
        XCTAssertTrue(output.contains("colored"))
        let command = GitLogRedactor.command(["add", "--", "line\nbreak\u{2028}next\u{85}line"], root: root)
        XCTAssertTrue(command.modified)
        XCTAssertFalse(command.text.contains("\n"))
        XCTAssertFalse(command.text.contains("\u{2028}"))
        XCTAssertFalse(command.text.contains("\u{85}"))
    }

    func testAuthorizationQuotedValuesAndTruncatedLinesDoNotLeak() {
        let root = URL(fileURLWithPath: "/example-project")
        let boundary = "-----" + "BEGIN " + "PRIVATE KEY" + "-----"
        let samples = ["Authorization: Bearer opaque-value", "password=\"opaque-first opaque-tail\"", "\"api_key\": \"opaque-value\"",
                       "token='opaque-first opaque-tail'", boundary + "\nopaque-value\n"]
        for sample in samples {
            let text = GitLogRedactor.redact(sample, root: root)
            XCTAssertFalse(text.contains("opaque"))
        }
        let incomplete = Data("safe line\npartial sensitive value".utf8)
        let output = GitLogRedactor.output(incomplete, truncated: true, root: root)
        XCTAssertEqual(output.text, "safe line\n")
        XCTAssertTrue(output.truncated)
        let escaped = GitLogRedactor.output(Data(repeating: 1, count: 32 * 1024), truncated: false, root: root)
        XCTAssertLessThanOrEqual(escaped.text.utf8.count, 32 * 1024)
        XCTAssertTrue(escaped.truncated, "Escaping control bytes can also exceed the display budget")
    }

    func testQuotedReplayPathsAreRedactedBeforeCommandFormatting() {
        let root = URL(fileURLWithPath: "/example-workspace/quoted'folder")
        let editor = GitCommandFormatter.quote(root.appendingPathComponent("sequence-editor.sh").path)
        let command = GitLogRedactor.command(["-c", "sequence.editor=/bin/sh " + editor, "rebase", "--interactive"], root: root)
        XCTAssertTrue(command.modified)
        XCTAssertFalse(command.text.contains("example-workspace"))
        XCTAssertFalse(command.text.contains("quoted"))
    }
}
