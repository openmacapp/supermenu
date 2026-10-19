import XCTest
import GitKit
@testable import SuperMenuGit

final class GitWorkspaceTests: XCTestCase {
    func testSquashPreservesTreeAndReplaysDescendants() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let first = try repo.commit("one", content: "1")
        let second = try repo.commit("two", content: "2")
        _ = try repo.commit("three", content: "3")
        let originalTree = try repo.git(["rev-parse", "HEAD^{tree}"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        var plan = try await workspace.preview(.squash, selected: [first, second])
        plan.message = "Combined"
        try await workspace.execute(plan)
        XCTAssertEqual(try repo.git(["rev-parse", "HEAD^{tree}"]), originalTree)
        XCTAssertEqual(try repo.git(["rev-list", "--count", "HEAD"]), "2")
        XCTAssertEqual(try repo.git(["log", "--format=%s", "--reverse"]), "Combined\nthree")
    }

    func testRevertCreatesNewCommitAndStalePreviewIsRejected() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("one", content: "1")
        let second = try repo.commit("two", content: "2")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let plan = try await workspace.preview(.revert, selected: [second])
        try await workspace.execute(plan)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "1")
        XCTAssertEqual(try repo.git(["rev-list", "--count", "HEAD"]), "3")
        do {
            try await workspace.execute(plan)
            XCTFail("A stale preview must not run")
        } catch {}
    }
}

struct Fixture {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("SuperMenu Git '测试' \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "SuperMenu Tests"])
        _ = try git(["config", "user.email", "tests@example.invalid"])
        _ = try git(["config", "commit.gpgsign", "false"])
    }
    func remove() { try? FileManager.default.removeItem(at: url) }
    @discardableResult func commit(_ message: String, content: String, file: String = "file.txt") throws -> String {
        try content.write(to: url.appendingPathComponent(file), atomically: true, encoding: .utf8)
        _ = try git(["add", "--", file])
        _ = try git(["commit", "-m", message])
        return try git(["rev-parse", "HEAD"])
    }
    @discardableResult func git(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = url
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw NSError(domain: text, code: Int(process.terminationStatus)) }
        return text
    }
}
