import Foundation
import GitKit

/// These files are planned inputs to Git, not evidence of completed commands.
public struct GitCommandFile: Equatable, Sendable, Identifiable {
    public let name: String
    public let content: String
    public var id: String { name }
}

public struct GitCommandPreview: Sendable {
    public let arguments: [String]
    public let files: [GitCommandFile]
    public var command: String {
        ([GitRunner.defaultGitPath] + arguments).map(GitCommandFormatter.quote).joined(separator: " ")
    }
}

public enum GitCommandFormatter {
    /// POSIX shell display/copy only. Execution continues to pass argument arrays.
    public static func quote(_ value: String) -> String {
        let safe = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/:=+@"
        if !value.isEmpty, value.allSatisfy({ safe.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension GitWorkspace {
    /// Resolving the scratch directory is read-only; preview never creates it.
    public func commandPreview(for plan: HistoryPlan) async throws -> GitCommandPreview {
        switch plan.action {
        case .revert, .reset, .cherryPick:
            return GitCommandPreview(arguments: try GitPlanCommands.directArguments(for: plan), files: [])
        case .squash, .rebase, .reword, .drop:
            return try GitPlanCommands.replay(for: plan, directory: await gitPath("supermenu-replay"))
        }
    }
}

/// The preview and executor share these pure builders so flags, ordering, edited
/// messages and grouping have one source of truth.
enum GitPlanCommands {
    static func directArguments(for plan: HistoryPlan) throws -> [String] {
        switch plan.action {
        case .cherryPick:
            let expected = Set(plan.selected.map(\.id))
            guard !expected.isEmpty, plan.entries.count == expected.count,
                  Set(plan.entries.map(\.id)) == expected,
                  plan.entries.allSatisfy({ $0.action == .pick && !$0.commit.isMerge }) else {
                throw WorkspaceFailure("git.error.cherryPickOrder")
            }
            // Explicit arguments retain the order confirmed in the editor.
            // Default Git behavior stops on empty/redundant patches for review.
            return ["cherry-pick", "--no-edit", "--no-walk=unsorted"] + plan.entries.map(\.id)
        case .revert:
            return ["revert", "--no-edit"] + plan.affected.map(\.id)
        case .reset:
            guard let target = plan.selected.first else { throw WorkspaceFailure("git.error.selection") }
            return ["reset", "--\(plan.resetMode.rawValue)", target.id]
        case .squash, .rebase, .reword, .drop:
            throw WorkspaceFailure("git.error.replay")
        }
    }

    static func replay(for plan: HistoryPlan, directory: URL) throws -> GitCommandPreview {
        let entries = try plan.validatedReplayEntries()
        var groups: [[ReplayEntry]] = []
        for entry in entries {
            if entry.action == .pick || entry.action == .reword || groups.isEmpty {
                groups.append([entry])
            } else {
                groups[groups.count - 1].append(entry)
            }
        }
        var files: [GitCommandFile] = []
        var todo: [String] = []
        for (index, group) in groups.enumerated() {
            for entry in group {
                let command: String
                switch entry.action {
                case .pick, .reword: command = "pick"
                case .squash, .fixup: command = "fixup"
                case .drop: command = "drop"
                }
                todo.append("\(command) \(entry.id)")
            }
            let retained = group.filter { $0.action != .drop }
            guard let first = retained.first else { continue }
            let original = ReplayEntry(first.commit).message
            let message = ([first.action == .reword ? first.message : original] +
                retained.dropFirst().filter { $0.action == .squash }.map(\.message)).joined(separator: "\n\n")
            if retained.count > 1 || message != original {
                let name = "message-\(index)"
                files.append(GitCommandFile(name: name, content: message))
                let file = directory.appendingPathComponent(name)
                // Pick/fixup preserve an originally empty message; edited reword
                // and squash messages still require text in the shared validator.
                let allowEmptyMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " --allow-empty-message" : ""
                todo.append("exec \(GitCommandFormatter.quote(GitRunner.defaultGitPath)) commit --amend --allow-empty\(allowEmptyMessage) --file=\(GitCommandFormatter.quote(file.path))")
            }
        }
        let todoFile = directory.appendingPathComponent("todo")
        files.append(GitCommandFile(name: "todo", content: todo.joined(separator: "\n") + "\n"))
        files.append(GitCommandFile(name: "sequence-editor.sh", content:
            "#!/bin/sh\nexec /bin/cp " + GitCommandFormatter.quote(todoFile.path) + " \"$1\"\n"))
        let editor = directory.appendingPathComponent("sequence-editor.sh")
        let command = "/bin/sh " + GitCommandFormatter.quote(editor.path)
        let arguments = ["-c", "sequence.editor=\(command)", "rebase", "--interactive",
                         "--no-autosquash", "--no-autostash", "--no-update-refs",
                         "--reapply-cherry-picks", "--reschedule-failed-exec", "--keep-empty", "--empty=keep"] +
                        (plan.base.map { [$0] } ?? ["--root"])
        return GitCommandPreview(arguments: arguments, files: files)
    }
}
