import XCTest
@testable import SuperMenuGit

final class GitDiffTests: XCTestCase {
    func testLiteralPathsAndLargePatchAreBounded() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("Base", content: "original\n", file: "[sample].txt")
        _ = try repo.commit("Other", content: "unrelated\n", file: "s.txt")
        let head = try repo.commit("Large change", content: String(repeating: "large change line\n", count: 80_000), file: "[sample].txt")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let comparison = GitComparison(from: try repo.git(["rev-parse", "HEAD^"]), to: head)
        let files = try await workspace.changedFiles(in: comparison)
        XCTAssertEqual(files.map(\.path), ["[sample].txt"])
        let patch = try await workspace.fileDiff(in: comparison, file: files[0])
        XCTAssertTrue(patch.truncated)
        XCTAssertLessThanOrEqual(patch.text.utf8.count, GitDiffPreview.byteLimit + 3)
        XCTAssertLessThanOrEqual(patch.text.filter { $0 == "\n" }.count, GitDiffPreview.lineLimit)
        XCTAssertFalse(patch.text.contains("unrelated"))
    }

    func testRenameBinaryAndRootComparisons() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let root = try repo.commit("Root", content: "hello\n", file: "old\tname.txt")
        _ = try repo.git(["mv", "old\tname.txt", "new\nname.txt"])
        _ = try repo.git(["commit", "-m", "Rename"])
        let head = try repo.git(["rev-parse", "HEAD"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let rename = GitComparison(from: root, to: head)
        let files = try await workspace.changedFiles(in: rename)
        XCTAssertEqual(files.first?.oldPath, "old\tname.txt")
        XCTAssertEqual(files.first?.path, "new\nname.txt")
        let patch = try await workspace.fileDiff(in: rename, file: files[0])
        XCTAssertTrue(patch.text.contains("similarity index 100%"))
        let initial = GitComparison(from: nil, to: root)
        let initialFiles = try await workspace.changedFiles(in: initial)
        let rootPatch = try await workspace.fileDiff(in: initial, file: initialFiles[0])
        XCTAssertTrue(rootPatch.text.contains("+hello"))
        let reverse = GitComparison(from: nil, to: root, reversed: true)
        let removed = try await workspace.changedFiles(in: reverse)
        XCTAssertEqual(removed.first?.status, "D")
        let reversePatch = try await workspace.fileDiff(in: reverse, file: removed[0])
        XCTAssertTrue(reversePatch.text.contains("-hello"))
        try Data([0, 1, 2, 3]).write(to: repo.url.appendingPathComponent("image.bin"))
        _ = try repo.git(["add", "."])
        _ = try repo.git(["commit", "-m", "Binary"])
        let binary = GitComparison(from: head, to: try repo.git(["rev-parse", "HEAD"]))
        let binaryFiles = try await workspace.changedFiles(in: binary)
        let binaryPatch = try await workspace.fileDiff(in: binary, file: binaryFiles[0])
        XCTAssertTrue(binaryPatch.isBinary)
    }

    func testMergeUsesFirstParentAndOperationPreviewsKeepDirection() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let root = try repo.commit("Base", content: "base\n")
        _ = try repo.git(["checkout", "-b", "topic"])
        _ = try repo.commit("Topic", content: "topic\n", file: "topic.txt")
        _ = try repo.git(["checkout", "main"])
        let parent = try repo.commit("Main", content: "main\n", file: "main.txt")
        _ = try repo.git(["merge", "--no-ff", "topic", "-m", "Merge topic"])
        let head = try repo.git(["rev-parse", "HEAD"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let files = try await workspace.changedFiles(in: GitComparison(from: parent, to: head))
        XCTAssertEqual(files.map(\.path), ["topic.txt"])
        let reset = try await workspace.preview(.reset, selected: [root])
        let resetFiles = try await workspace.changedFiles(in: reset.comparisons[0])
        XCTAssertEqual(Set(resetFiles.map(\.path)), ["main.txt", "topic.txt"])
        XCTAssertTrue(resetFiles.allSatisfy { $0.status == "D" })
        let next = try repo.commit("Update base", content: "updated\n")
        let revert = try await workspace.preview(.revert, selected: [next])
        let revertFiles = try await workspace.changedFiles(in: revert.comparisons[0])
        let patch = try await workspace.fileDiff(in: revert.comparisons[0], file: revertFiles[0])
        XCTAssertTrue(patch.text.contains("-updated"))
        XCTAssertTrue(patch.text.contains("+base"))
    }

    func testManyFilesAndByteLimitOnSingleLongLine() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        for index in 0..<250 {
            try "content\n".write(to: repo.url.appendingPathComponent("file-\(index).txt"), atomically: true, encoding: .utf8)
        }
        let head = try repo.commit("Many files", content: String(repeating: "x", count: 800_000), file: "long.txt")
        _ = try repo.git(["add", "."])
        _ = try repo.git(["commit", "-m", "Remaining files"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let comparison = GitComparison(from: nil, to: head)
        let files = try await workspace.changedFiles(in: comparison)
        let patch = try await workspace.fileDiff(in: comparison, file: files[0])
        XCTAssertTrue(patch.truncated)
        XCTAssertLessThanOrEqual(patch.text.utf8.count, GitDiffPreview.byteLimit + 3)
        let manyFiles = try await workspace.changedFiles(in: GitComparison(from: head, to: try repo.git(["rev-parse", "HEAD"])))
        XCTAssertEqual(manyFiles.count, 250)
        let one = try await workspace.fileDiff(in: GitComparison(from: head, to: try repo.git(["rev-parse", "HEAD"])), file: manyFiles[120])
        XCTAssertEqual(one.text.components(separatedBy: "diff --git ").count, 2)
        XCTAssertFalse(one.truncated)
    }

    func testLargeInputIsSkippedBeforeGeneratingPatch() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let base = try repo.commit("Large input", content: String(repeating: "x", count: GitDiffPreview.inputByteLimit + 1))
        let head = try repo.commit("Replace large input", content: "small\n")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let comparison = GitComparison(from: base, to: head)
        let files = try await workspace.changedFiles(in: comparison)
        let patch = try await workspace.fileDiff(in: comparison, file: files[0])
        XCTAssertTrue(patch.skippedLargeFile)
        XCTAssertTrue(patch.text.isEmpty)
    }

    func testBinaryForcedToTextDoesNotReachTextPreview() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        _ = try repo.commit("Attributes", content: "*.dat diff\n", file: ".gitattributes")
        try Data([0, 1, 2, 3, 10, 65]).write(to: repo.url.appendingPathComponent("payload.dat"))
        try repo.git(["add", "payload.dat"])
        try repo.git(["commit", "-m", "Binary forced to text"])
        let comparison = GitComparison(from: try repo.git(["rev-parse", "HEAD^"]), to: try repo.git(["rev-parse", "HEAD"]))
        let workspace = try await GitWorkspace.open(at: repo.url)
        let files = try await workspace.changedFiles(in: comparison)
        let patch = try await workspace.fileDiff(in: comparison, file: XCTUnwrap(files.first))
        XCTAssertTrue(patch.isBinary, "Attributes must not force NUL bytes into the text renderer")
        XCTAssertFalse(patch.text.contains("\0"))
    }

    func testGitlinkPreviewIgnoresLocalSubmoduleDisplayConfiguration() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let base = try repo.commit("Base", content: "base")
        try repo.git(["update-index", "--add", "--cacheinfo", "160000,\(base),dependency"])
        try repo.git(["commit", "-m", "Gitlink"])
        try repo.git(["config", "diff.submodule", "log"])
        try repo.git(["config", "diff.ignoreSubmodules", "all"])
        let comparison = GitComparison(from: base, to: try repo.git(["rev-parse", "HEAD"]))
        let workspace = try await GitWorkspace.open(at: repo.url)
        let files = try await workspace.changedFiles(in: comparison)
        XCTAssertEqual(files.map(\.path), ["dependency"], "A changed gitlink must not disappear due to local config")
        let patch = try await workspace.fileDiff(in: comparison, file: XCTUnwrap(files.first))
        XCTAssertTrue(patch.text.contains("Subproject commit " + base))
        XCTAssertFalse(patch.text.contains("+base"), "Do not recursively diff submodule contents")
    }

    func testExternalDiffAndTextConversionAreNeverExecuted() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let driver = repo.url.appendingPathComponent("driver.sh")
        try "#!/bin/sh\necho invoked > driver-was-run\n".write(to: driver, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: driver.path)
        _ = try repo.commit("Attributes", content: "*.txt diff=custom\n", file: ".gitattributes")
        let base = try repo.commit("Base", content: "before\n")
        let head = try repo.commit("Next", content: "after\n")
        try repo.git(["config", "diff.external", "./driver.sh"])
        try repo.git(["config", "diff.custom.command", "./driver.sh"])
        try repo.git(["config", "diff.custom.textconv", "./driver.sh"])
        let workspace = try await GitWorkspace.open(at: repo.url)
        let comparison = GitComparison(from: base, to: head)
        let files = try await workspace.changedFiles(in: comparison)
        let patch = try await workspace.fileDiff(in: comparison, file: XCTUnwrap(files.first))
        XCTAssertTrue(patch.text.contains("-before"))
        XCTAssertTrue(patch.text.contains("+after"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("driver-was-run").path))
    }

    func testCancelledDiffDoesNotReturnContent() async throws {
        let repo = try Fixture()
        defer { repo.remove() }
        let head = try repo.commit("Content", content: "line\n")
        let workspace = try await GitWorkspace.open(at: repo.url)
        let comparison = GitComparison(from: nil, to: head)
        let files = try await workspace.changedFiles(in: comparison)
        let task = Task {
            return try await workspace.fileDiff(in: comparison, file: files[0])
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled work must not publish content") }
        catch is CancellationError {}
    }
}
