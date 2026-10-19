import Foundation
import GitKit

extension GitWorkspace {
    /// Files live under this worktree's Git directory so a conflicted rebase can
    /// continue after the app exits. Git itself retains the original HEAD for abort.
    func replay(_ plan: HistoryPlan) async throws {
        var entries = plan.entries
        let expected = Set(plan.affected.map(\.id))
        guard entries.count == expected.count, Set(entries.map(\.id)) == expected,
              entries.first?.combineWithPrevious == false else {
            throw WorkspaceFailure("git.error.replay")
        }
        if plan.action == .squash {
            guard !plan.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorkspaceFailure("git.error.message")
            }
            let selected = Set(plan.selected.map(\.id))
            var first = true
            for index in entries.indices where selected.contains(entries[index].id) {
                entries[index].combineWithPrevious = !first
                first = false
            }
        }
        guard entries.allSatisfy({ !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw WorkspaceFailure("git.error.message")
        }
        let directory = try await gitPath("supermenu-replay")
        // execute already rejected active operations; only inactive scratch files are removed.
        if FileManager.default.fileExists(atPath: directory.path) { try await removeReplayFiles() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var groups: [[ReplayEntry]] = []
        for entry in entries {
            if entry.combineWithPrevious { groups[groups.count - 1].append(entry) }
            else { groups.append([entry]) }
        }
        var todo: [String] = []
        for (index, group) in groups.enumerated() {
            for (offset, entry) in group.enumerated() {
                todo.append("\(offset == 0 ? "pick" : "fixup") \(entry.id)")
            }
            let first = group[0]
            let original = ReplayEntry(first.commit).message
            let isSquashedSelection = plan.action == .squash && plan.selected.contains { $0.id == first.id }
            let message = isSquashedSelection ? plan.message : group.map(\.message).joined(separator: "\n\n")
            if group.count > 1 || message != original {
                let file = directory.appendingPathComponent("message-\(index)")
                try message.write(to: file, atomically: true, encoding: .utf8)
                todo.append("exec \(Self.shellQuote(GitRunner.defaultGitPath)) commit --amend --file=\(Self.shellQuote(file.path))")
            }
        }
        let todoFile = directory.appendingPathComponent("todo")
        try (todo.joined(separator: "\n") + "\n").write(to: todoFile, atomically: true, encoding: .utf8)
        let editor = directory.appendingPathComponent("sequence-editor.sh")
        try ("#!/bin/sh\nexec /bin/cp " + Self.shellQuote(todoFile.path) + " \"$1\"\n")
            .write(to: editor, atomically: true, encoding: .utf8)
        let command = "/bin/sh " + Self.shellQuote(editor.path)
        do {
            try await runner.run(["-c", "sequence.editor=\(command)", "rebase", "--interactive",
                                  "--no-autosquash", "--no-autostash", "--no-update-refs",
                                  "--reapply-cherry-picks", "--reschedule-failed-exec", "--keep-empty", "--empty=keep"] +
                                 (plan.base.map { [$0] } ?? ["--root"]))
        } catch {
            if try await operation() == nil { try await removeReplayFiles() }
            throw error
        }
        try await removeReplayFiles()
    }

    func removeReplayFiles() async throws {
        guard try await operation() == nil else { return }
        let directory = try await gitPath("supermenu-replay")
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
