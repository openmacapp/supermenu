import Foundation
import GitKit

public enum HistoryAction: String, CaseIterable, Sendable {
    case squash, revert, rebase, reset, cherryPick, reword, drop
}

public enum HistoryReset: String, CaseIterable, Sendable {
    case soft, mixed, hard
}

public enum ReplayAction: String, CaseIterable, Sendable {
    case pick, reword, squash, fixup, drop

    public var editsMessage: Bool { self == .reword || self == .squash }
}

public struct ReplayEntry: Identifiable, Sendable {
    public let commit: Commit
    public var id: String { commit.id }
    public var message: String
    public var action: ReplayAction

    init(_ commit: Commit) {
        self.commit = commit
        self.message = commit.summary + (commit.body.isEmpty ? "" : "\n\n" + commit.body)
        self.action = .pick
    }
}

/// A preview captures the repository state. Editable fields describe user intent;
/// execute revalidates them and the captured state before touching history.
public struct HistoryPlan: Identifiable, Sendable {
    public let id = UUID()
    public let action: HistoryAction
    public let selected: [Commit]
    public let affected: [Commit]
    public let published: Set<String>
    public let snapshot: RepositorySnapshot
    public let comparisons: [GitComparison]
    public var message: String
    public var resetMode: HistoryReset = .soft
    public var entries: [ReplayEntry]
    let base: String?

    /// The UI and compiler use the same validation, including after reordering.
    public var replayValidationError: String? {
        switch action {
        case .squash, .rebase, .reword, .drop:
            do { _ = try validatedReplayEntries(); return nil }
            catch { return (error as? WorkspaceFailure)?.key ?? "git.error.replay" }
        default: return nil
        }
    }

    func validatedReplayEntries() throws -> [ReplayEntry] {
        var result = entries
        let expected = Set(affected.map(\.id))
        guard !expected.isEmpty, result.count == expected.count, Set(result.map(\.id)) == expected else {
            throw WorkspaceFailure("git.error.replay")
        }
        if action == .squash {
            let selectedIDs = Set(selected.map(\.id))
            var first = true
            for index in result.indices where selectedIDs.contains(result[index].id) {
                result[index].action = first ? .reword : .fixup
                if first { result[index].message = message }
                first = false
            }
        }
        let retained = result.filter { $0.action != .drop }
        guard !retained.isEmpty || base != nil else { throw WorkspaceFailure("git.error.dropAllHistory") }
        if let first = retained.first, first.action == .squash || first.action == .fixup {
            throw WorkspaceFailure("git.error.replay")
        }
        guard result.filter({ $0.action.editsMessage }).allSatisfy({ !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw WorkspaceFailure("git.error.message")
        }
        return result
    }
}

public struct RepositorySnapshot: Equatable, Sendable {
    public let head: String
    public let branch: String
    public let status: String
    let refs: String
}

public enum InterruptedOperation: String, Sendable {
    case rebase, revert, cherryPick, merge
}

public struct WorkspaceFailure: Error, LocalizedError, Sendable {
    public let key: String
    public var errorDescription: String? { key }
    init(_ key: String) { self.key = key }
}
