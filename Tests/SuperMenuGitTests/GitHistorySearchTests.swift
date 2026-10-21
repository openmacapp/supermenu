import XCTest
import CryptoKit
import Darwin
@testable import SuperMenuGit

final class GitHistorySearchTests: XCTestCase {
    func testSearchesBeyondInitialHistoryAndPagesMatches() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let oldest = try repo.commit("needle oldest", content: "base")
        // commit-tree avoids hundreds of working-tree writes and hooks.
        let tree = try repo.git(["rev-parse", "HEAD^{tree}"])
        var head = oldest
        for index in 0..<205 {
            head = try repo.git(["commit-tree", tree, "-p", head, "-m", "ordinary \(index)"])
        }
        try repo.git(["update-ref", "refs/heads/main", head])
        let newest = try repo.commit("needle newest", content: "new")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let initial = try await workspace.history()
        XCTAssertFalse(initial.commits.contains { $0.id == oldest })
        let start = Date()
        let query = GitHistoryQuery(text: "needle", field: .message)
        let first = try await workspace.searchHistory(query, limit: 1)
        XCTAssertEqual(first.commits.map(\.id), [newest])
        XCTAssertEqual(first.nextSkip, 1)
        let second = try await workspace.searchHistory(query, skip: 1, limit: 1)
        XCTAssertEqual(second.commits.map(\.id), [oldest])
        XCTAssertNil(second.nextSkip)
        print("History search: 207 synthetic commits, two pages, \(Date().timeIntervalSince(start)) seconds")
    }

    func testLiteralTextAuthorAndReadOnlyScope() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let base = try repo.commit("-选项 [a].* 'quoted' 한글 日本語", content: "base")
        try repo.git(["checkout", "-b", "topic"])
        let topic = try repo.commit("only topic", content: "topic")
        try repo.git(["checkout", "main"])
        try "dirty".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let workspace = try await GitWorkspace.open(at: repo.url)
        let before = try await workspace.snapshot()
        let index = try repo.git(["ls-files", "--stage"])
        for text in ["-选项", "[a].*", "'quoted'", "한글", "日本語"] {
            let page = try await workspace.searchHistory(.init(text: text, field: .message))
            XCTAssertEqual(page.commits.map(\.id), [base])
        }
        let absent = try await workspace.searchHistory(.init(text: "o.*topic", field: .message))
        XCTAssertTrue(absent.commits.isEmpty)
        let author = try await workspace.searchHistory(.init(text: "SuperMenu Tests", field: .author))
        XCTAssertEqual(Set(author.commits.map(\.id)), [base, topic])
        let scoped = try await workspace.searchHistory(.init(text: "topic", field: .message, reference: "refs/heads/main"))
        XCTAssertTrue(scoped.commits.isEmpty)
        let sha = try await workspace.searchHistory(.init(text: String(topic.prefix(8)), field: .sha))
        XCTAssertEqual(sha.commits.map(\.id), [topic])
        await assertFailure("git.error.commitOutsideScope") {
            _ = try await workspace.searchHistory(.init(text: topic, field: .sha, reference: "refs/heads/main"))
        }
        await assertFailure("git.error.referenceMissing") {
            _ = try await workspace.searchHistory(.init(text: "", field: .message, reference: "refs/heads/missing"))
        }
        let after = try await workspace.snapshot()
        XCTAssertEqual(before, after)
        XCTAssertEqual(index, try repo.git(["ls-files", "--stage"]))
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "dirty")
    }

    func testInvalidQueriesEmptyRepositoryAndCancellation() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let workspace = try await GitWorkspace.open(at: repo.url)
        let empty = try await workspace.searchHistory(.init(text: "", field: .message))
        XCTAssertTrue(empty.commits.isEmpty)
        for text in ["--all", "HEAD~1", "abc", "hello", String(repeating: "a", count: 65)] {
            await assertFailure("git.error.invalidSHA") {
                _ = try await workspace.searchHistory(.init(text: text, field: .sha))
            }
        }
        for text in ["one\ntwo", "zero\0byte"] {
            await assertFailure("git.error.invalidSearch") {
                _ = try await workspace.searchHistory(.init(text: text, field: .message))
            }
        }
        let task = Task {
            try Task.checkCancellation()
            return try await workspace.searchHistory(.init(text: "", field: .message))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled search must not produce results") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testAmbiguousHashAndNonCommitAreRejected() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("base", content: "base")
        let tree = try repo.git(["rev-parse", "HEAD^{tree}"])
        var prefixes: [String: String] = [:]
        var collision: (String, String, String)?
        // Pigeonhole bound: two valid synthetic commits must share 4 hex digits.
        for index in 0...65_536 {
            let body = "tree \(tree)\nauthor Example <example@example.invalid> 1700000000 +0000\ncommitter Example <example@example.invalid> 1700000000 +0000\n\nCandidate \(index)\n"
            let object = Data("commit \(body.utf8.count)\0".utf8) + Data(body.utf8)
            let prefix = Insecure.SHA1.hash(data: object).prefix(2).map { String(format: "%02x", $0) }.joined()
            if let earlier = prefixes[prefix] { collision = (prefix, earlier, body); break }
            prefixes[prefix] = body
        }
        let pair = try XCTUnwrap(collision)
        let file = repo.url.appendingPathComponent("object.txt")
        for body in [pair.1, pair.2] {
            try body.write(to: file, atomically: true, encoding: .utf8)
            try repo.git(["hash-object", "-t", "commit", "-w", file.path])
        }
        let workspace = try await GitWorkspace.open(at: repo.url)
        await assertFailure("git.error.ambiguousSHA") {
            _ = try await workspace.searchHistory(.init(text: pair.0, field: .sha))
        }
        await assertFailure("git.error.commitMissing") {
            _ = try await workspace.searchHistory(.init(text: tree, field: .sha))
        }
    }

    func testOversizedResponseIsNotAnEmptyOrPartialSuccess() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let message = repo.url.appendingPathComponent("message.txt")
        try ("Large message\n\n" + String(repeating: "x", count: 8 * 1024 * 1024)).write(
            to: message, atomically: true, encoding: .utf8)
        try repo.git(["commit", "--allow-empty", "-F", message.path])
        let workspace = try await GitWorkspace.open(at: repo.url)
        await assertFailure("git.error.searchLimited") {
            _ = try await workspace.searchHistory(.init(text: "Large message", field: .message))
        }
    }

    func testDetachedHEADAndControlCharactersInMessages() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("base", content: "base")
        try repo.git(["checkout", "--detach"])
        let detached = try repo.commit("Detached \u{1e} \u{1f} commit", content: "new")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let found = try await workspace.searchHistory(.init(text: detached.uppercased(), field: .sha))
        XCTAssertEqual(found.commits.map(\.id), [detached])
        XCTAssertEqual(found.commits.first?.summary, "Detached \u{1e} \u{1f} commit")
        await assertFailure("git.error.commitOutsideScope") {
            _ = try await workspace.searchHistory(.init(text: detached, field: .sha, reference: "refs/heads/main"))
        }
    }

    func testLargeHistorySearchAndReaderCancellationReapsHelpers() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        var stream = ""
        for index in 0..<10_000 {
            let message = index == 0 ? "earliest target" : "Synthetic \(index)"
            stream += "commit refs/heads/main\ncommitter Example <example@example.invalid> 1700000000 +0000\ndata \(message.utf8.count)\n\(message)\n\n"
        }
        let input = repo.url.appendingPathComponent("import.txt")
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
        let workspace = try await GitWorkspace.open(at: repo.url)
        let start = ContinuousClock.now
        let found = try await workspace.searchHistory(.init(text: "earliest target", field: .message))
        XCTAssertEqual(found.commits.map(\.summary), ["earliest target"])
        print("PERF 10000 synthetic commits, oldest match: \(start.duration(to: .now))")

        let script = repo.url.appendingPathComponent("wait.sh")
        try "#!/bin/sh\nsleep 30 &\necho $! > child.pid\nwait\n".write(to: script, atomically: true, encoding: .utf8)
        let task = Task {
            try await BoundedGitRead.read(root: repo.url,
                arguments: ["-c", "alias.search-wait=!sh ./wait.sh", "search-wait"], byteLimit: 1024)
        }
        let pidFile = repo.url.appendingPathComponent("child.pid")
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: pidFile.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = try XCTUnwrap(Int32(try String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled reader must not return data") }
        catch is CancellationError {}
        let reapDeadline = ContinuousClock.now + .seconds(5)
        while kill(pid, 0) == 0, ContinuousClock.now < reapDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(kill(pid, 0), -1, "Cancellation must terminate Git's helper as well")
        XCTAssertEqual(errno, ESRCH)
    }

    private func assertFailure(_ key: String, operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(key)") }
        catch let error as WorkspaceFailure { XCTAssertEqual(error.key, key) }
        catch { XCTFail("Unexpected error: \(error)") }
    }
}
