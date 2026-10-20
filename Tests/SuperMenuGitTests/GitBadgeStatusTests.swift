import XCTest

@testable import SuperMenuGit

final class GitBadgeStatusTests: XCTestCase {
    func testParserAggregatesConflictPriorityAndBothRenameParents() throws {
        let snapshot = try GitBadgeStatus.parse(
            Data("?? new/file\0 M src/file\0UU src/deep/conflict\0R  target/name\0old/name\0".utf8))
        XCTAssertEqual(snapshot.states["."], "conflict")
        XCTAssertEqual(snapshot.states["src"], "conflict")
        XCTAssertEqual(snapshot.states["new"], "untracked")
        XCTAssertEqual(snapshot.states["target"], "modified")
        XCTAssertEqual(snapshot.states["old"], "modified")
        XCTAssertNil(snapshot.states["clean"])
    }
    func testMalformedAndOversizedInputNeverPublishesPartialStatus() {
        for data in [
            Data(" M unterminated".utf8), Data("R  target\0".utf8), Data([32, 77, 32, 255, 0]),
            Data(" M ../outside\0".utf8),
        ] {
            XCTAssertThrowsError(try GitBadgeStatus.parse(data))
        }
        XCTAssertThrowsError(try GitBadgeStatus.parse(Data("?? path\0".utf8), byteBudget: 10))
        XCTAssertThrowsError(try GitBadgeStatus.parse(Data("?? a\0?? b\0".utf8), recordLimit: 1))
        XCTAssertTrue(try GitBadgeStatus.parse(Data()).states.isEmpty)
    }
    func testRealRepositoryStatusRespectsIgnoresAndHandlesBinaryWithoutDiff() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("Base", content: "base")
        try "ignored/\n".write(
            to: repo.url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: repo.url.appendingPathComponent("ignored"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 9 * 1024 * 1024).write(
            to: repo.url.appendingPathComponent("ignored/blob"))
        try Data([0, 255, 0]).write(to: repo.url.appendingPathComponent("binary"))
        try "changed".write(
            to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let identity = try await GitBadgeStatus.discover(at: repo.url)
        let snapshot = try await GitBadgeStatus.read(identity)
        XCTAssertEqual(snapshot.states["file.txt"], "modified")
        XCTAssertEqual(snapshot.states["binary"], "untracked")
        XCTAssertNil(snapshot.states["ignored"])
        XCTAssertLessThanOrEqual(snapshot.cost, 4 * 1024 * 1024)
    }
    func testDeadlineDoesNotWaitForInheritedOutputPipe() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let start = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await BoundedGitRead.read(
                root: repo.url,
                arguments: ["-c", "alias.badge-delay=!trap '' TERM; sleep 2; printf done", "badge-delay"],
                byteLimit: 1024, timeout: 0.05)
            XCTFail("Expected deadline")
        } catch { XCTAssertEqual((error as? WorkspaceFailure)?.key, "git.error.diffTimeout") }
        XCTAssertLessThan(
            ProcessInfo.processInfo.systemUptime - start, 1, "Inherited pipe must not extend the deadline")
    }

    func testThousandTenThousandAndHundredThousandPathBudgets() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let identity = try await GitBadgeStatus.discover(at: repo.url)
        var previous = 0
        for count in [1_000, 10_000, 100_000] {
            for index in previous..<count {
                FileManager.default.createFile(
                    atPath: repo.url.appendingPathComponent("f\(index)").path, contents: Data())
            }
            previous = count
            let start = ContinuousClock.now
            if count <= 10_000 {
                let snapshot = try await GitBadgeStatus.read(identity)
                XCTAssertEqual(snapshot.states.count, count + 1)
                XCTAssertEqual(snapshot.states["."], "untracked")
                XCTAssertLessThanOrEqual(snapshot.cost, 4 * 1024 * 1024)
                print("BADGE PERF paths=\(count) duration=\(start.duration(to: .now)) cost=\(snapshot.cost)")
            } else {
                do {
                    _ = try await GitBadgeStatus.read(identity)
                    XCTFail("Oversized status must not publish partial state")
                } catch { XCTAssertEqual(error as? GitBadgeFailure, .overBudget) }
                print("BADGE PERF paths=\(count) bounded rejection=\(start.duration(to: .now))")
            }
        }
    }

    func testLinkedWorktreesHaveSeparateIdentityAndUnbornRepositoryWorks() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let unborn = try await GitBadgeStatus.discover(at: repo.url)
        let empty = try await GitBadgeStatus.read(unborn)
        XCTAssertTrue(empty.states.isEmpty)
        _ = try repo.commit("Base", content: "base")
        let other = repo.url.appendingPathComponent("worktree")
        try repo.git(["worktree", "add", "-b", "secondary", other.path])
        let identity = try await GitBadgeStatus.discover(at: other)
        XCTAssertNotEqual(identity.gitDirectory, unborn.gitDirectory)
        XCTAssertEqual(identity.commonDirectory, unborn.commonDirectory)
        XCTAssertNotEqual(identity.root, unborn.root)
    }
}
