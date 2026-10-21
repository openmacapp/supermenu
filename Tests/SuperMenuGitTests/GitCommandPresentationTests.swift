import XCTest
import GitKit
@testable import SuperMenuGit

final class GitCommandPresentationTests: XCTestCase {
    func testResetModesSharePreviewAndExecutionArguments() async throws {
        for mode in HistoryReset.allCases {
            let repo = try Fixture()
            defer { repo.remove() }
            let first = try repo.commit("one", content: "1")
            _ = try repo.commit("two", content: "2")
            let workspace = try await GitWorkspace.open(at: repo.url)
            var plan = try await workspace.preview(.reset, selected: [first])
            plan.resetMode = mode
            let preview = try await workspace.commandPreview(for: plan)
            XCTAssertEqual(preview.arguments, ["reset", "--" + mode.rawValue, first])
            XCTAssertTrue(preview.files.isEmpty)
            try await workspace.execute(plan)
            XCTAssertEqual(try repo.git(["rev-parse", "HEAD"]), first)
            XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), mode == .hard ? "1" : "2")
            XCTAssertEqual(try repo.git(["show", ":file.txt"]), mode == .soft ? "2" : "1")
        }
    }

    func testRevertPreviewUsesNewestFirstWithoutChangingRepository() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("one", content: "1")
        let second = try repo.commit("two", content: "2")
        let third = try repo.commit("three", content: "3")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.revert, selected: [second, third])
        let before = try await workspace.snapshot()
        let preview = try await workspace.commandPreview(for: plan)
        XCTAssertEqual(preview.arguments, ["revert", "--no-edit", third, second])
        let after = try await workspace.snapshot()
        XCTAssertEqual(before, after)
        try await workspace.execute(plan)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "1")
    }

    func testRootSquashPreviewIsReadOnlyAndMatchesExecutedMessage() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "1")
        let second = try repo.commit("two", content: "2")
        let workspace = try await GitWorkspace.open(at: repo.url)
        var plan = try await workspace.preview(.squash, selected: [first, second])
        plan.message = "合并 'quoted' \"message\"\n\n$(touch unwanted)"
        let gitDirectory = repo.url.appendingPathComponent(".git")
        let filesBefore = try FileManager.default.subpathsOfDirectory(atPath: gitDirectory.path).sorted()
        let before = try await workspace.snapshot()
        let preview = try await workspace.commandPreview(for: plan)
        XCTAssertEqual(preview.arguments.last, "--root")
        XCTAssertTrue(preview.arguments.contains("--no-update-refs"))
        XCTAssertTrue(preview.arguments.contains("--no-autostash"))
        let todo = try XCTUnwrap(preview.files.first { $0.name == "todo" })
        XCTAssertTrue(todo.content.hasPrefix("pick \(first)\nfixup \(second)\nexec "))
        XCTAssertEqual(preview.files.first { $0.name == "message-0" }?.content, plan.message)
        XCTAssertNotNil(preview.files.first { $0.name == "sequence-editor.sh" })
        let after = try await workspace.snapshot()
        XCTAssertEqual(before, after)
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: gitDirectory.path).sorted(), filesBefore)
        try await workspace.execute(plan)
        XCTAssertEqual(try repo.git(["log", "-1", "--format=%B"]), plan.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("unwanted").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: gitDirectory.appendingPathComponent("supermenu-replay").path))
    }

    func testReplayEditsUpdateTodoAndMessages() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "1")
        let second = try repo.commit("two", content: "2", file: "second.txt")
        let third = try repo.commit("three", content: "3", file: "third.txt")
        let workspace = try await GitWorkspace.open(at: repo.url)
        var plan = try await workspace.preview(.rebase, selected: [second])
        let original = try await workspace.commandPreview(for: plan)
        XCTAssertEqual(original.arguments.last, first)
        plan.entries.swapAt(0, 1)
        plan.entries[0].message = "Renamed"
        plan.entries[0].action = .reword
        plan.entries[1].action = .squash
        let edited = try await workspace.commandPreview(for: plan)
        let todo = try XCTUnwrap(edited.files.first { $0.name == "todo" })
        XCTAssertTrue(todo.content.hasPrefix("pick \(third)\nfixup \(second)\nexec "))
        XCTAssertEqual(edited.files.first { $0.name == "message-0" }?.content, "Renamed\n\ntwo")
        XCTAssertNotEqual(original.files, edited.files)
        try await workspace.execute(plan)
        XCTAssertEqual(try repo.git(["log", "-1", "--format=%B"]), "Renamed\n\ntwo")
        XCTAssertEqual(try repo.git(["rev-list", "--count", "HEAD"]), "2")
    }

    func testInvalidReplayEditsAreRejectedBeforeWritingFiles() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "1")
        _ = try repo.commit("two", content: "2")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let original = try await workspace.preview(.rebase, selected: [first])
        var emptyMessage = original
        emptyMessage.entries[0].message = " \n "
        emptyMessage.entries[0].action = .reword
        var firstCombined = original
        firstCombined.entries[0].action = .squash
        var missingEntry = original
        missingEntry.entries.removeLast()
        for (plan, key) in [(emptyMessage, "git.error.message"), (firstCombined, "git.error.replay"), (missingEntry, "git.error.replay")] {
            do {
                _ = try await workspace.commandPreview(for: plan)
                XCTFail("An invalid plan must not have an executable preview")
            } catch let failure as WorkspaceFailure { XCTAssertEqual(failure.key, key) }
            do {
                try await workspace.execute(plan)
                XCTFail("Invalid editor contents must not change history")
            } catch let failure as WorkspaceFailure { XCTAssertEqual(failure.key, key) }
            let snapshot = try await workspace.snapshot()
            XCTAssertEqual(snapshot, original.snapshot)
            XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent(".git/supermenu-replay").path))
        }
    }

    func testCommandFormattingRoundTripsArgumentsWithoutShellExpansion() throws {
        let arguments = ["", "ordinary", "--option=value", "a b", "中文", "quote'\"", "line\nbreak", "$(printf bad)", "`echo bad`", "a;echo bad", "*.swift"]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s\\0' " + arguments.map(GitCommandFormatter.quote).joined(separator: " ")]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), arguments.joined(separator: "\0") + "\0")
    }
}
