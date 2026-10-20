import XCTest
import GitKit
@testable import SuperMenuGit

final class GitRobustnessTests: XCTestCase {
    func testDivergentBranchSelectionsAreRejectedAndOtherRefsSurviveSquash() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let root = try repo.commit("Root", content: "root")
        try repo.git(["checkout", "-b", "topic"])
        let topic = try repo.commit("Topic", content: "topic", file: "topic.txt")
        try repo.git(["checkout", "main"])
        let first = try repo.commit("Main one", content: "one")
        let head = try repo.commit("Main two", content: "two")
        try repo.git(["update-ref", "refs/remotes/origin/topic", topic])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let history = try await workspace.history()
        XCTAssertEqual(Set(history.commits.map(\.id)), [root, topic, first, head])
        for action in [HistoryAction.reset, .rebase, .revert] {
            do { _ = try await workspace.preview(action, selected: [topic]); XCTFail("Foreign branch selection") }
            catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.ancestry") }
        }
        let tree = try repo.git(["rev-parse", "HEAD^{tree}"])
        var plan = try await workspace.preview(.squash, selected: [first, head])
        plan.message = "Combined"
        try await workspace.execute(plan)
        XCTAssertEqual(try repo.git(["symbolic-ref", "--short", "HEAD"]), "main")
        XCTAssertEqual(try repo.git(["rev-parse", "HEAD^{tree}"]), tree)
        XCTAssertEqual(try repo.git(["rev-parse", "topic"]), topic)
        XCTAssertEqual(try repo.git(["rev-parse", "refs/remotes/origin/topic"]), topic)
    }

    func testExternalBranchSwitchInvalidatesPreviewEvenAtSameCommit() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let root = try repo.commit("Root", content: "root")
        let head = try repo.commit("Next", content: "next")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.reset, selected: [root])
        try repo.git(["checkout", "-b", "same-head"])
        do { try await workspace.execute(plan); XCTFail("Changed branch must invalidate confirmation") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.stale") }
        XCTAssertEqual(try repo.git(["rev-parse", "HEAD"]), head)
        try repo.git(["checkout", "--detach", head])
        let history = try await workspace.history()
        XCTAssertTrue(history.commits.contains { $0.id == head })
        do { _ = try await workspace.preview(.revert, selected: [head]); XCTFail("Detached mutation") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.detached") }
    }

    func testHistoricalPreviewDoesNotFollowSymlinksOrReadUntrackedFiles() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let root = try repo.commit("Root", content: "committed")
        try FileManager.default.createSymbolicLink(atPath: repo.url.appendingPathComponent("link").path,
                                                  withDestinationPath: "untracked.txt")
        try repo.git(["add", "link"])
        try repo.git(["commit", "-m", "Link"])
        let head = try repo.git(["rev-parse", "HEAD"])
        try "NOT IN HISTORY".write(to: repo.url.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: repo.url.appendingPathComponent("file.txt"))
        let before = try repo.git(["status", "--porcelain"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let comparison = GitComparison(from: root, to: head)
        let files = try await workspace.changedFiles(in: comparison)
        XCTAssertEqual(files.map(\.path), ["link"])
        let patch = try await workspace.fileDiff(in: comparison, file: XCTUnwrap(files.first))
        XCTAssertTrue(patch.text.contains("+untracked.txt"))
        XCTAssertFalse(patch.text.contains("NOT IN HISTORY"))
        XCTAssertEqual(try repo.git(["status", "--porcelain"]), before)
    }

    func testMissingObjectAndInvalidTextEncodingAreExplicitErrors() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let root = try repo.commit("Root", content: "root")
        try Data([0xff, 0xfe, 0x41, 0x42]).write(to: repo.url.appendingPathComponent("legacy.txt"))
        try repo.git(["add", "legacy.txt"])
        try repo.git(["commit", "-m", "Non UTF8"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let comparison = GitComparison(from: root, to: try repo.git(["rev-parse", "HEAD"]))
        let files = try await workspace.changedFiles(in: comparison)
        do { _ = try await workspace.fileDiff(in: comparison, file: XCTUnwrap(files.first)); XCTFail("Lossy text") }
        catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.diffEncoding") }
        do {
            _ = try await workspace.changedFiles(in: GitComparison(from: root, to: String(repeating: "0", count: 40)))
            XCTFail("Missing object must not appear as an empty diff")
        } catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.diff") }
    }

    func testBoundedReadsReportTruncationDeadlineAndCancellation() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("Large", content: String(repeating: "line\n", count: 500_000))
        let object = try repo.git(["rev-parse", "HEAD:file.txt"])
        let read = try await BoundedGitRead.read(root: repo.url, arguments: ["cat-file", "blob", object], byteLimit: 100)
        XCTAssertTrue(read.truncated)
        XCTAssertEqual(read.data.count, 100)
        do {
            _ = try await BoundedGitRead.read(root: repo.url, arguments: ["cat-file", "blob", object], byteLimit: 4_000_000, timeout: 0)
            XCTFail("Expired read")
        } catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.diffTimeout") }
        for _ in 0..<20 {
            let task = Task {
                try await BoundedGitRead.read(root: repo.url, arguments: ["cat-file", "blob", object], byteLimit: 4_000_000)
            }
            // Cancel after the read has had a chance to start, not just before creating it.
            try await Task.sleep(nanoseconds: 1_000_000)
            task.cancel()
            do { _ = try await task.value; XCTFail("Cancelled output") }
            catch is CancellationError {}
        }
    }

    func testNestedFileListAndRepeatedDiffReadPerformance() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let base = try repo.commit("Base", content: "base")
        for directory in 0..<100 {
            let folder = repo.url.appendingPathComponent("Sources/Module-\(directory)/Nested")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in 0..<50 {
                try "file \(directory)/\(file)\n".write(to: folder.appendingPathComponent("File-\(file).txt"),
                                                     atomically: true, encoding: .utf8)
            }
        }
        try repo.git(["add", "Sources"])
        try repo.git(["commit", "-m", "Five thousand nested files"])
        let comparison = GitComparison(from: base, to: try repo.git(["rev-parse", "HEAD"]))
        let workspace = try await GitWorkspace.open(at: repo.url)
        let start = ContinuousClock.now
        let files = try await workspace.changedFiles(in: comparison)
        let listTime = start.duration(to: .now)
        XCTAssertEqual(files.count, 5_000)
        XCTAssertEqual(Set(files.map(\.path)).count, 5_000)
        var latencies: [Double] = []
        for index in 0..<40 {
            let file = files[index * 113]
            let start = ContinuousClock.now
            let patch = try await workspace.fileDiff(in: comparison, file: file)
            let elapsed = start.duration(to: .now).components
            latencies.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
            XCTAssertTrue(patch.text.contains(file.path))
            XCTAssertEqual(patch.text.components(separatedBy: "diff --git ").count, 2)
            XCTAssertFalse(patch.truncated)
        }
        latencies.sort()
        print("PERF 5000 nested files: list=\(listTime); 40 file reads median=\(latencies[20])ms p95=\(latencies[37])ms max=\(latencies[39])ms")
    }
}
