import Foundation
import GitKit

/// GitKit supplies repository discovery, parsing and graph layout. This actor owns the
/// narrower SuperMenu history workflow and prevents overlapping mutations.
public actor GitWorkspace {
    public nonisolated let root: URL
    let service: CLIGitService
    let runner: GitRunner
    private var mutating = false
    var operationStore = GitOperationStore()

    private init(service: CLIGitService) {
        self.service = service
        self.root = service.root
        self.runner = GitRunner(workingDirectory: service.root)
    }

    public static func open(at url: URL) async throws -> GitWorkspace {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let service = try await CLIGitService(directory: isDirectory ? url : url.deletingLastPathComponent())
        return GitWorkspace(service: service)
    }

    public func history(limit: Int = 200, reference: String? = nil) async throws -> CommitPage {
        if let reference {
            // Accept an exact enumerated ref, never revision expressions/options.
            guard try await references().contains(where: { $0.id == reference }) else {
                throw WorkspaceFailure("git.error.referenceMissing")
            }
            let resolved = try await runner.runRaw(["rev-parse", "--verify", "--end-of-options", reference + "^{commit}"])
            guard resolved.succeeded else { throw WorkspaceFailure("git.error.referenceMissing") }
            let sha = resolved.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            return try await service.log(skip: 0, limit: limit, revisions: [sha])
        }
        let hasHead = try await runner.runRaw(["rev-parse", "--verify", "HEAD"])
        // An unborn branch can still have remote history.
        return try await service.log(skip: 0, limit: limit, revisions: hasHead.succeeded ? ["--all", "HEAD"] : ["--all"])
    }

    public func snapshot() async throws -> RepositorySnapshot {
        let head = try await runner.runRaw(["rev-parse", "--verify", "HEAD"])
        let branch = try await runner.runRaw(["symbolic-ref", "--quiet", "--short", "HEAD"])
        return RepositorySnapshot(
            head: head.succeeded ? head.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            branch: branch.succeeded ? branch.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            status: try await runner.runString(["status", "--porcelain=v1", "-z", "--untracked-files=all"]),
            refs: try await runner.runString(["for-each-ref", "--format=%(refname) %(objectname)"]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public func files(commit: String) async throws -> [FileChange] {
        try await service.commitChanges(sha: commit)
    }

    public func operation() async throws -> InterruptedOperation? {
        for (marker, operation) in [("rebase-merge", InterruptedOperation.rebase), ("rebase-apply", .rebase),
                                    ("REVERT_HEAD", .revert), ("CHERRY_PICK_HEAD", .cherryPick), ("MERGE_HEAD", .merge)] {
            let path = try await runner.runString(["rev-parse", "--git-path", marker]).trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL.path) {
                return operation
            }
        }
        // A sequence may pause between commits without its per-commit HEAD marker.
        let todo = try await gitPath("sequencer/todo")
        if let text = try? String(contentsOf: todo) {
            if text.hasPrefix("revert ") { return .revert }
            if text.hasPrefix("pick ") { return .cherryPick }
        }
        return nil
    }

    public func conflicts() async throws -> [String] {
        let data = try await runner.run(["diff", "--name-only", "--diff-filter=U", "-z"])
        return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
    }

    public func preview(_ action: HistoryAction, selected ids: Set<String>) async throws -> HistoryPlan {
        guard !mutating, try await operation() == nil else { throw WorkspaceFailure("git.error.inProgress") }
        let before = try await snapshot()
        guard !before.head.isEmpty, !ids.isEmpty else { throw WorkspaceFailure("git.error.selection") }
        guard before.status.isEmpty else { throw WorkspaceFailure("git.error.dirty") }
        guard !before.branch.isEmpty else { throw WorkspaceFailure("git.error.detached") }
        if action == .cherryPick, ids.count > 200 { throw WorkspaceFailure("git.error.rangeTooLarge") }

        // Obtain actual commit objects, never interpolate user-supplied revision syntax.
        guard ids.allSatisfy({ $0.count == 40 || $0.count == 64 }) else { throw WorkspaceFailure("git.error.selection") }
        guard ids.allSatisfy({ $0.allSatisfy(\.isHexDigit) }) else { throw WorkspaceFailure("git.error.selection") }
        let commits = try await service.log(skip: 0, limit: ids.count, revisions: ["--no-walk=sorted"] + ids.sorted())
        let selected = commits.commits
        guard selected.count == ids.count else { throw WorkspaceFailure("git.error.selection") }
        var affected = selected
        var base: String?
        var entries: [ReplayEntry] = []
        var comparisons: [GitComparison] = []

        switch action {
        case .cherryPick:
            affected = try await orderedCherryPicks(selected)
            entries = affected.map(ReplayEntry.init)
            comparisons = affected.map {
                GitComparison(from: $0.parents.first, to: $0.id, title: $0.shortID + "  " + $0.summary)
            }
        case .squash, .rebase, .reword, .drop:
            if action == .squash && ids.count < 2 { throw WorkspaceFailure("git.error.squashSelection") }
            if action == .reword && ids.count != 1 { throw WorkspaceFailure("git.error.selectOne") }
            let chain = try await service.log(skip: 0, limit: 10_000, revisions: ["--first-parent", "HEAD"])
            let indices = chain.commits.indices.filter { ids.contains(chain.commits[$0].id) }
            guard indices.count == ids.count, let oldest = indices.max() else { throw WorkspaceFailure("git.error.ancestry") }
            if action == .squash, let newest = indices.min(), oldest - newest + 1 != ids.count {
                throw WorkspaceFailure("git.error.contiguous")
            }
            affected = Array(chain.commits[...oldest].reversed())
            guard affected.allSatisfy({ !$0.isMerge }) else { throw WorkspaceFailure("git.error.merge") }
            base = affected.first?.parents.first
            entries = affected.map(ReplayEntry.init)
            if action == .reword || action == .drop {
                for index in entries.indices where ids.contains(entries[index].id) {
                    entries[index].action = action == .reword ? .reword : .drop
                }
                if action == .drop, base == nil, entries.allSatisfy({ $0.action == .drop }) {
                    throw WorkspaceFailure("git.error.dropAllHistory")
                }
            }
            comparisons = [GitComparison(from: base, to: before.head)]
        case .revert:
            guard selected.allSatisfy({ !$0.isMerge }) else { throw WorkspaceFailure("git.error.merge") }
            // Topological order makes dependent commits undo newest first.
            let ordered = try await runner.runString(["rev-list", "--topo-order", "HEAD"])
                .split(separator: "\n").map(String.init).filter { ids.contains($0) }
            guard ordered.count == ids.count else { throw WorkspaceFailure("git.error.ancestry") }
            let byID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
            affected = ordered.compactMap { byID[$0] }
            comparisons = affected.map {
                GitComparison(from: $0.parents.first, to: $0.id, reversed: true,
                              title: $0.shortID + "  " + $0.summary)
            }
        case .reset:
            guard selected.count == 1, let target = selected.first else { throw WorkspaceFailure("git.error.selectOne") }
            let ancestry = try await runner.runRaw(["merge-base", "--is-ancestor", target.id, before.head])
            guard ancestry.succeeded else { throw WorkspaceFailure("git.error.ancestry") }
            let removed = try await service.log(skip: 0, limit: 10_000, revisions: ["\(target.id)..\(before.head)"])
            guard removed.nextSkip == nil else { throw WorkspaceFailure("git.error.rangeTooLarge") }
            affected = removed.commits
            comparisons = [GitComparison(from: before.head, to: target.id)]
        }
        let remoteIDs = Set(try await runner.runString(["rev-list", "--remotes"]).split(separator: "\n").map(String.init))
        guard try await snapshot() == before else { throw WorkspaceFailure("git.error.stale") }
        return HistoryPlan(action: action, selected: selected, affected: affected,
                           published: Set(affected.map(\.id)).intersection(remoteIDs), snapshot: before,
                           comparisons: comparisons, message: affected.filter { ids.contains($0.id) }.map { ReplayEntry($0).message }.joined(separator: "\n\n"),
                           entries: entries, base: base)
    }

    public func execute(_ plan: HistoryPlan) async throws {
        try await recordOperation(action: plan.action.rawValue) { record in
            guard !mutating else { throw WorkspaceFailure("git.error.inProgress") }
            mutating = true
            defer { mutating = false }
            guard try await operation() == nil else { throw WorkspaceFailure("git.error.inProgress") }
            guard try await snapshot() == plan.snapshot else { throw WorkspaceFailure("git.error.stale") }
            switch plan.action {
            case .squash, .rebase, .reword, .drop:
                try await replay(plan, record: &record)
            case .revert, .reset, .cherryPick:
                try await runMutation(GitPlanCommands.directArguments(for: plan), record: &record)
            }
        }
    }

    /// Resolutions are edited in the user's editor. This explicitly stages only
    /// the chosen conflicted path; it never stages unrelated working-tree files.
    public func markResolved(path: String) async throws {
        try await recordOperation(action: "resolved") { record in
            guard !mutating else { throw WorkspaceFailure("git.error.inProgress") }
            mutating = true
            defer { mutating = false }
            guard try await operation() != nil else { throw WorkspaceFailure("git.error.inProgress") }
            guard try await conflicts().contains(path) else { throw WorkspaceFailure("git.error.selection") }
            try await runMutation(["add", "--", path], record: &record)
        }
    }

    public func finishOperation(abort: Bool) async throws {
        try await recordOperation(action: abort ? "abort" : "continue") { record in
            guard !mutating else { throw WorkspaceFailure("git.error.inProgress") }
            mutating = true
            defer { mutating = false }
            guard let operation = try await operation() else { throw WorkspaceFailure("git.error.inProgress") }
            let command: String
            switch operation {
            case .rebase: command = "rebase"
            case .revert: command = "revert"
            case .cherryPick: command = "cherry-pick"
            case .merge: command = "merge"
            }
            if !abort, !(try await conflicts()).isEmpty { throw WorkspaceFailure("git.error.conflicts") }
            try await runMutation([command, abort ? "--abort" : "--continue"], record: &record)
            if try await self.operation() == nil { try await removeReplayFiles() }
        }
    }

    public func skipEmptyCherryPick() async throws {
        try await recordOperation(action: "skipCherryPick") { record in
            guard !mutating else { throw WorkspaceFailure("git.error.inProgress") }
            mutating = true
            defer { mutating = false }
            guard try await canSkipEmptyCherryPick() else { throw WorkspaceFailure("git.error.skipCherryPick") }
            try await runMutation(["cherry-pick", "--skip"], record: &record)
        }
    }

    func gitPath(_ path: String) async throws -> URL {
        let value = try await runner.runString(["rev-parse", "--git-path", path]).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: value, relativeTo: root).standardizedFileURL
    }

}
