import Foundation
import GitKit

public enum GitHistorySearchField: String, CaseIterable, Sendable {
    case message, author, sha
}

public struct GitHistoryQuery: Equatable, Sendable {
    public var text: String
    public var field: GitHistorySearchField
    public var reference: String?

    public init(text: String, field: GitHistorySearchField, reference: String? = nil) {
        self.text = text
        self.field = field
        self.reference = reference
    }
}

extension GitWorkspace {
    /// Searches the entire selected ancestry, then pages the matching commits.
    /// Reads are cancellable and bounded; a truncated page is never presented as complete.
    public func searchHistory(_ query: GitHistoryQuery, skip: Int = 0, limit: Int = 200) async throws -> CommitPage {
        guard skip >= 0, (1...200).contains(limit), query.text.utf8.count <= 4096,
              !query.text.contains(where: { $0 == "\0" || $0 == "\n" || $0 == "\r" }) else {
            throw WorkspaceFailure("git.error.invalidSearch")
        }
        let revisions = try await searchRevisions(reference: query.reference)
        var arguments = ["-c", "grep.ignoreCase=false", "log", "--topo-order", "--no-color", "--no-notes", "--no-show-signature",
                         "--encoding=UTF-8", "--decorate=short", "-z",
                         "--format=%H%x00%P%x00%an%x00%ae%x00%at%x00%cn%x00%ce%x00%ct%x00%s%x00%b%x00%D",
                         "--skip=\(skip)", "--max-count=\(limit + 1)"]
        if query.field == .sha && !query.text.isEmpty {
            let sha = try await searchCommit(query.text)
            // A commit is in scope iff excluding that scope leaves no ancestors
            // reachable from it. This also handles tags and detached HEAD.
            let outside = try await searchRead(["rev-list", "--max-count=1", sha, "--not"] + revisions + ["--"], byteLimit: 1024)
            guard outside.isEmpty else { throw WorkspaceFailure("git.error.commitOutsideScope") }
            arguments += ["--no-walk", sha]
        } else {
            if !query.text.isEmpty {
                arguments += ["--fixed-strings",
                              (query.field == .message ? "--grep=" : "--author=") + query.text]
            }
            arguments += revisions
        }
        arguments.append("--")
        let output = try await searchRead(arguments, byteLimit: 8 * 1024 * 1024)
        var commits = try Self.parseSearchCommits(output)
        let hasMore = commits.count > limit
        if hasMore { commits.removeLast(commits.count - limit) }
        return CommitPage(commits: commits, nextSkip: hasMore ? skip + limit : nil)
    }

    private func searchRevisions(reference: String?) async throws -> [String] {
        if let reference {
            guard try await references().contains(where: { $0.id == reference }) else {
                throw WorkspaceFailure("git.error.referenceMissing")
            }
            do {
                let data = try await searchRead(["rev-parse", "--verify", "--end-of-options", reference + "^{commit}"], byteLimit: 1024)
                return [String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)]
            } catch is CancellationError { throw CancellationError() }
            catch { throw WorkspaceFailure("git.error.referenceMissing") }
        }
        // --revs-only succeeds with no output for unborn HEAD; a detached HEAD
        // must be included explicitly because --all only enumerates refs.
        let head = try await searchRead(["rev-parse", "--revs-only", "HEAD"], byteLimit: 1024)
        let sha = String(decoding: head, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? ["--all"] : ["--all", sha]
    }

    private func searchCommit(_ input: String) async throws -> String {
        guard (4...64).contains(input.utf8.count), input.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { throw WorkspaceFailure("git.error.invalidSHA") }
        let data = try await searchRead(["rev-parse", "--disambiguate=" + input.lowercased()], byteLimit: 64 * 1024)
        let matches = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        guard !matches.isEmpty else { throw WorkspaceFailure("git.error.commitMissing") }
        guard matches.count == 1 else { throw WorkspaceFailure("git.error.ambiguousSHA") }
        let sha = matches[0]
        let type = try await searchRead(["cat-file", "-t", sha], byteLimit: 1024)
        guard String(decoding: type, as: UTF8.self) == "commit\n" else {
            throw WorkspaceFailure("git.error.commitMissing")
        }
        return sha
    }

    private func searchRead(_ arguments: [String], byteLimit: Int) async throws -> Data {
        do {
            let result = try await BoundedGitRead.read(root: root, arguments: arguments, byteLimit: byteLimit)
            guard !result.truncated else { throw WorkspaceFailure("git.error.searchLimited") }
            return result.data
        } catch let error as WorkspaceFailure {
            if error.key == "git.error.diffTimeout" { throw WorkspaceFailure("git.error.searchTimeout") }
            if error.key == "git.error.diff" { throw WorkspaceFailure("git.error.search") }
            throw error
        }
    }

    private static func parseSearchCommits(_ data: Data) throws -> [Commit] {
        guard !data.isEmpty else { return [] }
        guard let text = String(data: data, encoding: .utf8), data.last == 0 else {
            throw WorkspaceFailure("git.error.search")
        }
        var fields = text.components(separatedBy: "\0")
        fields.removeLast()
        guard fields.count.isMultiple(of: 11) else { throw WorkspaceFailure("git.error.search") }
        return try stride(from: 0, to: fields.count, by: 11).map { offset in
            let row = Array(fields[offset..<(offset + 11)])
            guard let authored = TimeInterval(row[4]), let committed = TimeInterval(row[7]) else {
                throw WorkspaceFailure("git.error.search")
            }
            return Commit(id: row[0], parents: row[1].split(separator: " ").map(String.init),
                          authorName: row[2], authorEmail: row[3], authorDate: Date(timeIntervalSince1970: authored),
                          committerName: row[5], committerEmail: row[6], commitDate: Date(timeIntervalSince1970: committed),
                          summary: row[8], body: row[9],
                          refs: row[10].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }
    }
}
