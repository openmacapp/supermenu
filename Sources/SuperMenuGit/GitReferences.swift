import Foundation
import GitKit

extension GitWorkspace {
    /// One bounded read. Ahead/behind counts are unnecessary for history filtering.
    public func references() async throws -> [Ref] {
        let result = try await BoundedGitRead.read(
            root: root,
            arguments: ["for-each-ref", "--sort=refname",
                        "--format=%(refname)%00%(objectname)%00%(objecttype)%00%(HEAD)%00%(symref)",
                        "refs/heads", "refs/remotes", "refs/tags"],
            byteLimit: 2 * 1024 * 1024
        )
        guard !result.truncated else { throw WorkspaceFailure("git.error.referencesLimited") }
        return String(decoding: result.data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5, fields[4].isEmpty,
                  fields[2] == "commit" || fields[2] == "tag" else { return nil }
            let id = fields[0]
            let kind: Ref.Kind
            let prefix: String
            if id.hasPrefix("refs/heads/") { kind = .localBranch; prefix = "refs/heads/" }
            else if id.hasPrefix("refs/remotes/") { kind = .remoteBranch; prefix = "refs/remotes/" }
            else if id.hasPrefix("refs/tags/") { kind = .tag; prefix = "refs/tags/" }
            else { return nil }
            return Ref(id: id, kind: kind, name: String(id.dropFirst(prefix.count)),
                       targetSHA: fields[1], isHead: fields[3] == "*")
        }
    }
}
