import Foundation
import GitKit

extension GitWorkspace {
    /// Walk parents before children, then keep only the chosen commits. Traversing
    /// intermediate commits matters even when the selection has gaps. Timestamps
    /// cannot establish dependency order, and patches may still depend on omitted
    /// commits; the confirmation view therefore shows the complete selected order.
    func orderedCherryPicks(_ commits: [Commit]) async throws -> [Commit] {
        guard commits.allSatisfy({ !$0.isMerge }) else {
            throw WorkspaceFailure("git.error.cherryPickMerge")
        }
        if commits.count == 1 { return commits }
        let byID = Dictionary(uniqueKeysWithValues: commits.map { ($0.id, $0) })
        let ids = byID.keys.sorted()
        var revisions = ids
        do {
            let common = try await BoundedGitRead.read(root: root,
                arguments: ["merge-base", "--octopus"] + ids, byteLimit: 128)
            let base = String(decoding: common.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !common.truncated, (base.count == 40 || base.count == 64), base.allSatisfy(\.isHexDigit) else {
                throw WorkspaceFailure("git.error.selection")
            }
            // Keep the common ancestor (it may be selected), prune its parents.
            // A large repository must still allow a small recent selection.
            revisions += ["--not", base + "^@"]
        } catch let failure as WorkspaceFailure where failure.key == "git.error.diff" {
            // Unrelated histories have no merge base. The full bounded walk still
            // validates every selected ID; cancellation/deadline errors propagate.
        }
        let result = try await BoundedGitRead.read(
            root: root, arguments: ["rev-list", "--topo-order", "--reverse", "--max-count=10001"] + revisions,
            byteLimit: 2 * 1024 * 1024, lineLimit: 10_000)
        guard !result.truncated else { throw WorkspaceFailure("git.error.rangeTooLarge") }
        let ordered = String(decoding: result.data, as: UTF8.self)
            .split(separator: "\n").compactMap { byID[String($0)] }
        guard ordered.count == commits.count else { throw WorkspaceFailure("git.error.selection") }
        return ordered
    }

    /// Skip is deliberately restricted to an empty paused pick. Git --skip can
    /// discard work, so never offer it for conflicts, staged resolutions or edits.
    public func canSkipEmptyCherryPick() async throws -> Bool {
        guard try await operation() == .cherryPick else { return false }
        let marker = try await gitPath("CHERRY_PICK_HEAD")
        guard FileManager.default.fileExists(atPath: marker.path) else { return false }
        return try await snapshot().status.isEmpty
    }
}
