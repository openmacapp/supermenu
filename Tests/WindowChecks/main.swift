import AppKit
import SwiftUI
import SuperMenuGit

/// Runs the real window manager in an isolated process and disposable repository.
@main
struct WindowChecks {
    @MainActor
    static func main() async {
        do { try await runChecks() }
        catch {
            print("Git window lifecycle: FAIL — \(error.localizedDescription)")
            exit(1)
        }
    }

    @MainActor
    private static func runChecks() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let manager = GitWindows.shared
        manager.open(root)
        try await waitUntil("repository window opens") { repositoryWindows.count == 1 }

        let originalModel = ModelReference(model(in: repositoryWindows[0]))
        precondition(originalModel.value != nil, "Expected the actual Git workspace view")
        try await waitUntil("initial load finishes") { originalModel.value?.unavailable == false }

        manager.open(root.appendingPathComponent("."))
        try await Task.sleep(for: .milliseconds(300))
        precondition(repositoryWindows.count == 1, "Opening the same repository must reuse its window")
        precondition(model(in: repositoryWindows[0]) === originalModel.value, "An open panel must keep its model")

        try await checkSearch(model(in: repositoryWindows[0])!)
        try await checkComparison(model(in: repositoryWindows[0])!, root: root)
        try await checkMergeNavigation(model(in: repositoryWindows[0])!, root: root)
        try await checkComparisonPagination(model(in: repositoryWindows[0])!, root: root)
        try await checkMutationErrorSurvivesReload(model(in: repositoryWindows[0])!, root: root)
        try await checkCherryPick(root: root.deletingLastPathComponent().appendingPathComponent("cherry-pick"))
        try await checkReplayEditing(root: root.deletingLastPathComponent().appendingPathComponent("replay-editing"))

        try await checkClosingDuringMutation(repositoryWindows[0], root: root)
        repositoryWindows[0].close()
        try await waitUntil("closed model is released") { originalModel.value == nil }
        precondition(repositoryWindows.isEmpty, "A closed repository must not retain a hidden window")

        manager.open(root)
        try await waitUntil("repository window opens") { repositoryWindows.count == 1 }
        let reopenedModel = ModelReference(model(in: repositoryWindows[0]))
        precondition(reopenedModel.value != nil, "Reopening must create a fresh model")
        try await waitUntil("reopened load finishes") { reopenedModel.value?.unavailable == false }
        reopenedModel.value?.search(text: "pending read", field: .message)
        repositoryWindows[0].close()
        try await waitUntil("reopened model is released") { reopenedModel.value == nil }
        print("Git window reuse, mutation close protection, close release and reopen: PASS")
    }

    @MainActor
    private static func checkSearch(_ model: GitWorkspaceModel) async throws {
        let original = model.commits.map(\.id)
        precondition(original.count == 2)
        model.search(text: "Initial", field: .message)
        // The first request is superseded before its debounce expires.
        model.search(text: "Second", field: .message)
        try await waitUntil("latest search finishes") { !model.searching }
        precondition(model.commits.map(\.summary) == ["Second"], "A stale query must not replace the newest result")
        precondition(model.selection == [original[0]], "Search should select its matching result")
        model.search(text: "does not exist", field: .message)
        try await waitUntil("empty search finishes") { !model.searching }
        precondition(model.commits.isEmpty && model.error == nil, "No matches is not a read failure")
        precondition(model.selection.isEmpty, "No matches must clear stale selection")
        model.locateHEAD()
        try await waitUntil("HEAD location finishes") { !model.searching }
        precondition(model.searchField == .sha && model.commits.map(\.id) == [original[0]])
        precondition(model.scrollTarget == original[0], "HEAD must be selected for scrolling")
        model.clearSearch()
        try await waitUntil("clear search finishes") { !model.searching }
        precondition(model.commits.map(\.id) == original && !model.hasSearch)
        print("Git model latest-query isolation, empty results, HEAD location and search clearing: PASS")
    }

    @MainActor
    private static func checkComparison(_ model: GitWorkspaceModel, root: URL) async throws {
        let newer = model.commits[0]
        let older = model.commits[1]
        model.selection = [newer.id, older.id]
        try await waitUntil("selection analysis finishes") { model.selectionSummary != nil }
        precondition(model.selectionSummary?.isContiguous == true)
        precondition(model.comparison?.from == older.id && model.comparison?.to == newer.id)
        let forward = model.comparison!.id
        model.swapComparison()
        precondition(model.comparison?.id != forward && model.comparison?.reversed == true)
        // Context actions use their clicked row, not the existing multi-selection.
        model.setComparisonBase(older)
        precondition(model.comparisonBase == older.id)
        model.compare(to: newer)
        precondition(model.selection == [newer.id] && model.comparison?.from == older.id)
        model.endComparison()
        model.navigate(to: older.id)
        precondition(model.selection == [older.id] && model.scrollTarget == older.id)
        if let reference = model.references.first(where: { $0.isHead }) {
            await model.setComparisonBase(reference: reference)
            precondition(model.comparisonBase == newer.id)
            await model.compare(toReference: reference)
            precondition(model.comparison?.from == newer.id && model.comparison?.to == newer.id)
            precondition(model.selection.isEmpty, "Ref comparison should not retain unrelated commit details")
            let pinned = model.comparison
            try git(root, ["commit", "--allow-empty", "-m", "Third"])
            await model.refresh()
            precondition(model.comparison == pinned, "Refreshing a moved ref must retain the captured comparison")
            precondition(model.selection.isEmpty, "Refreshing a reference comparison must not show unrelated HEAD details")
            precondition(model.comparisonBase == newer.id, "The pinned base must not follow its branch")
            let pendingComparison = Task { await model.compare(toReference: reference) }
            await Task.yield()
            model.clearSearch()
            await pendingComparison.value
            try await waitUntil("new history request finishes") { !model.unavailable }
            precondition(model.explicitComparison == nil, "A reference response must not overwrite a later history request")
        }
        model.endComparison()
        model.clearComparisonBase()
        precondition(model.comparisonBase == nil)
        model.navigate(to: newer.id)
        try await waitUntil("latest selection analysis finishes") { model.selectionSummary?.count == 1 }
        print("Git pair direction, context target, pinned reference comparison and parent navigation: PASS")
    }

    @MainActor
    private static func checkMergeNavigation(_ model: GitWorkspaceModel, root: URL) async throws {
        let branch = model.snapshot!.branch
        try git(root, ["checkout", "-b", "topic"])
        try git(root, ["commit", "--allow-empty", "-m", "Topic"])
        try git(root, ["checkout", branch])
        try git(root, ["commit", "--allow-empty", "-m", "Main"])
        try git(root, ["merge", "--no-ff", "topic", "-m", "Merge"])
        await model.refresh()
        let before = try await model.workspace.snapshot()
        model.search(text: "Merge", field: .message)
        try await waitUntil("merge search finishes") { !model.searching }
        let merge = model.selectedCommit!
        precondition(merge.parents.count == 2)
        precondition(model.comparison?.from == merge.parents[0])
        model.selectParent(merge.parents[1])
        precondition(model.comparison?.from == merge.parents[1], "Selecting the second parent must change the diff endpoint")
        model.navigate(to: merge.parents[1])
        try await waitUntil("unloaded parent navigation finishes") { !model.searching }
        precondition(model.selectedCommit?.id == merge.parents[1], "Parent outside the loaded rows must be located by SHA")
        let after = try await model.workspace.snapshot()
        precondition(before == after, "Browsing comparisons must not mutate repository state")
        model.clearSearch()
        try await waitUntil("full history returns") { !model.searching }
        print("Git merge parent selection and unloaded-parent navigation: PASS")
    }

    @MainActor
    private static func checkComparisonPagination(_ model: GitWorkspaceModel, root: URL) async throws {
        for index in 0..<205 {
            try git(root, ["commit", "--allow-empty", "-m", "Page entry \(index)"])
        }
        await model.refresh()
        precondition(model.hasMore, "The fixture must exercise a second history page")
        let reference = model.references.first { $0.isHead }!
        await model.setComparisonBase(reference: reference)
        await model.compare(toReference: reference)
        let pinned = model.comparison
        await model.refresh(more: true)
        guard model.comparison == pinned && model.selection.isEmpty else {
            throw NSError(domain: "WindowChecks", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "Loading another history page replaced a pinned comparison with unrelated selection"])
        }
        model.endComparison()
        model.clearComparisonBase()
        model.navigate(to: model.commits[0].id)
        print("Git history pagination preserves pinned comparison and empty selection: PASS")
    }

    private static func git(_ root: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = root
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "WindowChecks.Git", code: Int(process.terminationStatus)) }
    }

    @MainActor
    private static func checkCherryPick(root: URL) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try git(root, ["init", "-b", "main"])
        let file = root.appendingPathComponent("file.txt")
        try "base".write(to: file, atomically: true, encoding: .utf8)
        try git(root, ["add", "."])
        try git(root, ["commit", "-m", "base"])
        try git(root, ["checkout", "-b", "source"])
        try "source".write(to: file, atomically: true, encoding: .utf8)
        try git(root, ["commit", "-am", "source patch"])
        try git(root, ["checkout", "main"])
        let workspace = try await GitWorkspace.open(at: root)
        let model = GitWorkspaceModel(workspace: workspace, l10n: L10n(language: .english))
        defer { model.cancelSearch(); model.cancelInspection() }
        await model.refresh()
        let sourceRef = model.references.first { $0.id == "refs/heads/source" }!
        await model.browse(reference: sourceRef.id)
        try await waitUntil("source branch history loads") { !model.unavailable }
        let picked = model.commits.first { $0.summary == "source patch" }!.id
        precondition(model.blockedReason(for: .cherryPick, ids: [picked]) == nil)
        await model.prepare(.cherryPick, selection: [picked])
        let plan = model.plan!
        precondition(plan.snapshot.branch == "main", "Browsing source must not change target branch")
        precondition(plan.entries.map(\.id) == [picked])
        model.plan = nil
        await model.execute(plan)
        precondition(model.error == nil && model.snapshot?.branch == "main")
        precondition(model.operationRecords.last?.status == .succeeded)

        // A duplicate patch must expose Skip, not silently succeed or duplicate it.
        await model.prepare(.cherryPick, selection: [picked])
        let duplicate = model.plan!
        model.plan = nil
        await model.execute(duplicate)
        precondition(model.operation == .cherryPick && model.canSkipEmptyCherryPick)
        precondition(model.error != nil && model.operationRecords.last?.status == .interrupted)
        await model.skipEmptyCherryPick()
        precondition(model.operation == nil && !model.canSkipEmptyCherryPick && model.error == nil)

        try git(root, ["checkout", "source"])
        try "source again".write(to: file, atomically: true, encoding: .utf8)
        try git(root, ["commit", "-am", "conflicting patch"])
        try git(root, ["checkout", "main"])
        try "target".write(to: file, atomically: true, encoding: .utf8)
        try git(root, ["commit", "-am", "target patch"])
        await model.refresh()
        let conflict = model.commits.first { $0.summary == "conflicting patch" }!.id
        await model.prepare(.cherryPick, selection: [conflict])
        let conflictPlan = model.plan!
        model.plan = nil
        await model.execute(conflictPlan)
        precondition(model.operation == .cherryPick && model.conflicts == ["file.txt"])
        precondition(!model.canSkipEmptyCherryPick)
        try "resolved".write(to: file, atomically: true, encoding: .utf8)
        await model.markResolved("file.txt")
        await model.finish(abort: false)
        precondition(model.operation == nil && model.conflicts.isEmpty && model.error == nil)
        precondition(model.operationRecords.last?.status == .succeeded)
        print("Git cherry-pick target while browsing another branch, preview, logs, empty skip and real conflict resolution: PASS")
    }

    @MainActor
    private static func checkReplayEditing(root: URL) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try git(root, ["init", "-b", "main"])
        for name in ["one", "two", "three"] {
            try name.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
            try git(root, ["add", "--", name])
            try git(root, ["commit", "-m", name])
        }
        let workspace = try await GitWorkspace.open(at: root)
        let model = GitWorkspaceModel(workspace: workspace, l10n: L10n(language: .english))
        defer { model.cancelSearch(); model.cancelInspection() }
        await model.refresh()
        let middle = model.commits.first { $0.summary == "two" }!.id
        precondition(model.blockedReason(for: .reword, ids: Set(model.commits.map(\.id))) == "git.error.selectOne")
        await model.prepare(.reword, selection: [middle])
        var reword = model.plan!
        precondition(reword.entries.map(\.action) == [.reword, .pick])
        reword.entries[0].message = "renamed middle"
        model.plan = nil
        await model.execute(reword)
        precondition(model.error == nil && model.operation == nil)
        precondition(model.commits.map(\.summary) == ["three", "renamed middle", "one"])
        precondition(model.operationRecords.last?.action == "reword" && model.operationRecords.last?.status == .succeeded)

        let rewrittenMiddle = model.commits[1].id
        await model.prepare(.drop, selection: [rewrittenMiddle])
        let drop = model.plan!
        precondition(drop.entries.map(\.action) == [.drop, .pick])
        model.plan = nil
        await model.execute(drop)
        precondition(model.error == nil && model.operation == nil)
        precondition(model.commits.map(\.summary) == ["three", "one"])
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("two").path))
        precondition(model.operationRecords.last?.action == "drop" && model.operationRecords.last?.status == .succeeded)

        await model.prepare(.rebase, selection: [model.commits.last!.id])
        var invalid = model.plan!
        invalid.entries[0].action = .fixup
        precondition(invalid.replayValidationError == "git.error.replay")
        let previousHead = model.snapshot?.head
        model.plan = nil
        await model.execute(invalid)
        precondition(model.error != nil && model.snapshot?.head == previousHead)
        precondition(model.operationRecords.last?.status == .notStarted)
        print("Git reword/drop entry points, descendant replay, file removal, operation logs and invalid-plan feedback: PASS")
    }

    @MainActor
    private static func checkMutationErrorSurvivesReload(_ model: GitWorkspaceModel, root: URL) async throws {
        let head = model.snapshot?.head
        let plan = try await model.workspace.preview(.reset, selected: [model.commits.last!.id])
        let file = root.appendingPathComponent("changed-after-preview.txt")
        try "Synthetic pending change".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        await model.execute(plan)
        precondition(model.error != nil, "History reload must not erase a mutation error")
        precondition(model.snapshot?.head == head, "A stale preview must not move HEAD")
        precondition(model.operationRecords.last?.status == .notStarted, "Rejected plans must appear as not started")
        precondition(model.operationRecords.last?.command == nil, "Preflight rejection must not invent an executed command")
        await model.clearOperationRecords()
        precondition(model.operationRecords.isEmpty, "Clearing must update the visible model")
        print("Git mutation failure remains visible after history reload: PASS")
    }

    @MainActor
    private static func checkClosingDuringMutation(_ window: NSWindow, root: URL) async throws {
        guard let model = model(in: window), let target = model.commits.last else {
            throw NSError(domain: "WindowChecks", code: 2)
        }
        var plan = try await model.workspace.preview(.reset, selected: [target.id])
        plan.resetMode = .soft
        // A disposable Git hook holds the real mutation long enough to exercise
        // the native close event without adding test-only state to production.
        let hook = root.appendingPathComponent(".git/hooks/reference-transaction")
        try "#!/bin/sh\nif [ \"$1\" = prepared ]; then sleep 1; fi\n".write(
            to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        defer { try? FileManager.default.removeItem(at: hook) }
        let operation = Task { await model.execute(plan) }
        try await waitUntil("mutation starts") { model.isMutating }
        window.performClose(nil)
        precondition(window.isVisible, "An executing operation must keep its window")
        precondition(window.attachedSheet != nil, "A refused close must explain why")
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
            sheet.orderOut(nil)
        }
        await operation.value
        precondition(!model.isMutating && model.error == nil, "Closing must not interrupt the mutation")
        precondition(model.snapshot?.head == target.id, "The actual reset must complete")
        precondition(model.operationRecords.last?.status == .succeeded)
        precondition(model.operationRecords.last?.exitCode == 0)
    }

    private final class ModelReference {
        weak var value: GitWorkspaceModel?
        init(_ value: GitWorkspaceModel?) { self.value = value }
    }

    @MainActor
    private static var repositoryWindows: [NSWindow] {
        NSApp.windows.filter { $0.contentView is NSHostingView<GitWorkspaceView> }
    }

    @MainActor
    private static func model(in window: NSWindow) -> GitWorkspaceModel? {
        (window.contentView as? NSHostingView<GitWorkspaceView>)?.rootView.model
    }

    @MainActor
    private static func waitUntil(_ condition: String, _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "WindowChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: condition + " timed out"])
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
