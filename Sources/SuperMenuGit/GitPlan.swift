import Foundation
import GitKit

public enum HistoryAction: String, CaseIterable, Sendable {
    case squash, revert, rebase, reset
}

public enum HistoryReset: String, CaseIterable, Sendable {
    case soft, mixed, hard
}

public struct ReplayEntry: Identifiable, Sendable {
    public let commit: Commit
    public var id: String { commit.id }
    public var message: String
    public var combineWithPrevious: Bool

    init(_ commit: Commit) {
        self.commit = commit
        self.message = commit.summary + (commit.body.isEmpty ? "" : "\n\n" + commit.body)
        self.combineWithPrevious = false
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
    public let diff: String
    public var message: String
    public var resetMode: HistoryReset = .soft
    public var entries: [ReplayEntry]
    let base: String?
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
