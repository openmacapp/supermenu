import Foundation

extension GitWorkspace {
    /// Files live under this worktree's Git directory so a conflicted rebase can
    /// continue after the app exits. Git itself retains the original HEAD for abort.
    func replay(_ plan: HistoryPlan, record: inout GitOperationRecord) async throws {
        let directory = try await gitPath("supermenu-replay")
        let prepared = try GitPlanCommands.replay(for: plan, directory: directory)
        // execute already rejected active operations; only inactive scratch files are removed.
        if FileManager.default.fileExists(atPath: directory.path) { try await removeReplayFiles() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        for file in prepared.files {
            try file.content.write(to: directory.appendingPathComponent(file.name), atomically: true, encoding: .utf8)
        }
        do {
            try await runMutation(prepared.arguments, record: &record)
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
}
