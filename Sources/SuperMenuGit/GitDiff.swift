import Foundation
import GitKit

/// Immutable endpoints keep browsing and operation previews independent of the working tree.
/// A nil base means the empty tree; merge commits are compared with their first parent.
public struct GitComparison: Identifiable, Hashable, Sendable {
    public let from: String?
    public let to: String
    public let reversed: Bool
    public let title: String
    public var id: String { "\(from ?? "root")..\(to):\(reversed)" }

    public init(from: String?, to: String, reversed: Bool = false, title: String = "") {
        self.from = from
        self.to = to
        self.reversed = reversed
        self.title = title
    }

    func arguments(options: [String]) -> [String] {
        let common = ["--no-ext-diff", "--no-textconv", "--no-color", "--find-renames",
                      "--submodule=short", "--ignore-submodules=none"]
            + (reversed ? ["-R"] : []) + options
        if let from { return ["--literal-pathspecs", "diff"] + common + [from, to] }
        return ["--literal-pathspecs", "show", "--format=", "--root"] + common + [to]
    }
}

public struct GitChangedFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let oldPath: String?
    public let status: String
}

public struct GitDiffPreview: Sendable {
    public static let byteLimit = 512 * 1024
    public static let lineLimit = 10_000
    public static let inputByteLimit = 8 * 1024 * 1024
    public let text: String
    public let truncated: Bool
    public let skippedLargeFile: Bool
    private let binaryInput: Bool

    init(text: String, truncated: Bool = false, skippedLargeFile: Bool = false, binaryInput: Bool = false) {
        self.text = text
        self.truncated = truncated
        self.skippedLargeFile = skippedLargeFile
        self.binaryInput = binaryInput
    }

    public var isBinary: Bool {
        binaryInput || text.hasPrefix("Binary files ") || text.contains("\nBinary files ") || text.contains("\nGIT binary patch")
    }
}

extension GitWorkspace {
    public func changedFiles(in comparison: GitComparison) async throws -> [GitChangedFile] {
        try Task.checkCancellation()
        let result = try await BoundedGitRead.read(root: root,
            arguments: comparison.arguments(options: ["--name-status", "-z"]) + ["--"], byteLimit: 8 * 1024 * 1024)
        guard !result.truncated else { throw WorkspaceFailure("git.error.fileListLimit") }
        guard let text = String(data: result.data, encoding: .utf8) else {
            throw WorkspaceFailure("git.error.diffEncoding")
        }
        try Task.checkCancellation()
        // NUL separators preserve tabs, newlines, Unicode and literal pathspec characters.
        let tokens = text.split(separator: "\0", omittingEmptySubsequences: false)
        var files: [GitChangedFile] = []
        var index = 0
        while index + 1 < tokens.count {
            let status = String(tokens[index].prefix(1))
            let renamed = status == "R" || status == "C"
            let pathIndex = index + (renamed ? 2 : 1)
            guard pathIndex < tokens.count, !tokens[pathIndex].isEmpty else { break }
            files.append(GitChangedFile(path: String(tokens[pathIndex]),
                                        oldPath: renamed ? String(tokens[index + 1]) : nil, status: status))
            index = pathIndex + 1
        }
        return files
    }

    public func fileDiff(in comparison: GitComparison, file: GitChangedFile) async throws -> GitDiffPreview {
        let paths = [file.oldPath, file.path].compactMap { $0 }
        var inspectedBlobs: Set<String> = []
        // Inspect historical objects, never filesystem targets: symlinks and
        // gitlinks must not lead us into a working tree or an external directory.
        for revision in [comparison.from, comparison.to].compactMap({ $0 }) {
            let result = try await BoundedGitRead.read(root: root,
                arguments: ["--literal-pathspecs", "ls-tree", "-l", "-z", revision, "--"] + paths,
                byteLimit: 64 * 1024)
            guard !result.truncated else { throw WorkspaceFailure("git.error.diff") }
            for entry in String(decoding: result.data, as: UTF8.self).split(separator: "\0") {
                let metadata = entry.prefix { $0 != "\t" }.split(whereSeparator: \.isWhitespace)
                guard metadata.count == 4 else { throw WorkspaceFailure("git.error.diff") }
                // Gitlinks have no blob; --submodule=short renders only their object IDs.
                guard metadata[1] == "blob" else { continue }
                guard let size = Int(metadata[3]) else { throw WorkspaceFailure("git.error.diff") }
                if size > GitDiffPreview.inputByteLimit {
                    return GitDiffPreview(text: "", skippedLargeFile: true)
                }
                let objectID = String(metadata[2])
                guard inspectedBlobs.insert(objectID).inserted else { continue }
                let sample = try await BoundedGitRead.read(root: root,
                    arguments: ["cat-file", "blob", objectID], byteLimit: 8 * 1024)
                // Attributes can force binary bytes through Git's text diff. The
                // preview refuses control bytes even when that override is present.
                if sample.data.contains(where: { $0 < 32 && $0 != 9 && $0 != 10 && $0 != 13 }) {
                    return GitDiffPreview(text: "", binaryInput: true)
                }
            }
        }
        let result = try await BoundedGitRead.read(root: root,
            arguments: comparison.arguments(options: ["--patch", "--unified=3"]) + ["--"] + paths,
            byteLimit: GitDiffPreview.byteLimit, lineLimit: GitDiffPreview.lineLimit)
        // Also reject binary bytes beyond the sampling window. Never send them to TextKit.
        if result.data.contains(where: { $0 < 32 && $0 != 9 && $0 != 10 && $0 != 13 }) {
            return GitDiffPreview(text: "", binaryInput: true)
        }
        // A byte-limited preview may cut the final UTF-8 character. Only that
        // incomplete suffix may be dropped; invalid content is not silently replaced.
        var bytes = result.data
        var text = String(data: bytes, encoding: .utf8)
        if result.truncated {
            for _ in 0..<3 where text == nil && !bytes.isEmpty {
                bytes.removeLast()
                text = String(data: bytes, encoding: .utf8)
            }
        }
        guard let text else { throw WorkspaceFailure("git.error.diffEncoding") }
        return GitDiffPreview(text: text, truncated: result.truncated)
    }
}
