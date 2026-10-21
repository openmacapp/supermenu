import Foundation
import GitKit

public enum GitMainlineMembership: Sendable {
    case all, notAll, unknown
}

/// Read-only guidance for a selection. The operation preview remains the final
/// authority: repository state can change after this analysis is displayed.
public struct GitSelectionSummary: Sendable {
    public let count: Int
    public let mergeCount: Int
    public let isContiguous: Bool
    public let mainline: GitMainlineMembership
    public let rebaseBlockedReason: String?

    public var squashBlockedReason: String? {
        if count < 2 { return "git.error.squashSelection" }
        if let rebaseBlockedReason { return rebaseBlockedReason }
        return isContiguous ? nil : "git.error.contiguous"
    }
}

extension GitWorkspace {
    public func selectionSummary(for commits: [Commit]) async throws -> GitSelectionSummary {
        let ids = Set(commits.map(\.id))
        let mergeCount = commits.filter(\.isMerge).count
        let selectedParents = commits.compactMap { commit -> String? in
            guard let parent = commit.parents.first, ids.contains(parent) else { return nil }
            return parent
        }
        // A connected single-parent path has n-1 edges and no parent with two
        // selected children. Display order and author dates play no role here.
        let contiguous = !commits.isEmpty && mergeCount == 0 && ids.count == commits.count
            && selectedParents.count == commits.count - 1 && Set(selectedParents).count == selectedParents.count
        let head = try await inspectionHead()
        guard !head.isEmpty, !ids.isEmpty else {
            return GitSelectionSummary(count: commits.count, mergeCount: mergeCount, isContiguous: contiguous,
                                       mainline: .unknown, rebaseBlockedReason: "git.error.selection")
        }
        let result = try await BoundedGitRead.read(root: root,
            arguments: ["rev-list", "--first-parent", "--parents", "--max-count=10001", head, "--"],
            byteLimit: 2 * 1024 * 1024)
        let lines = String(decoding: result.data, as: UTF8.self).split(separator: "\n")
        // Drop the final record if a byte limit cut it in half.
        let completeLines = result.truncated ? Array(lines.dropLast()) : Array(lines)
        let rows = completeLines.prefix(10_000).map { $0.split(separator: " ") }
        let indices = rows.indices.filter { ids.contains(String(rows[$0][0])) }
        let complete = !result.truncated && lines.count <= 10_000
        let membership: GitMainlineMembership = indices.count == ids.count ? .all : (complete ? .notAll : .unknown)
        let reason: String?
        switch membership {
        case .unknown: reason = "git.selectionAnalysisLimited"
        case .notAll: reason = "git.error.ancestry"
        case .all:
            let oldest = indices.max()!
            reason = rows[...oldest].contains { $0.count > 2 } ? "git.error.merge" : nil
        }
        guard try await inspectionHead() == head else { throw WorkspaceFailure("git.error.stale") }
        return GitSelectionSummary(count: commits.count, mergeCount: mergeCount, isContiguous: contiguous,
                                   mainline: membership, rebaseBlockedReason: reason)
    }

    private func inspectionHead() async throws -> String {
        let result = try await BoundedGitRead.read(root: root,
            arguments: ["rev-parse", "--revs-only", "HEAD"], byteLimit: 1024)
        guard !result.truncated else { throw WorkspaceFailure("git.error.selection") }
        return String(decoding: result.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
