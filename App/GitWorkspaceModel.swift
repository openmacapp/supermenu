import AppKit
import SwiftUI
import GitKit
import SuperMenuGit

@MainActor
final class GitWorkspaceModel: ObservableObject {
    let workspace: GitWorkspace
    @Published var l10n: L10n
    @Published var commits: [Commit] = []
    @Published var graph = CommitGraph.empty
    @Published var selection: Set<String> = [] {
        didSet { if selection != oldValue { inspectSelection() } }
    }
    @Published var snapshot: RepositorySnapshot?
    @Published var operation: InterruptedOperation?
    @Published private(set) var canSkipEmptyCherryPick = false
    @Published var conflicts: [String] = []
    @Published var busy = false
    private(set) var isMutating = false
    @Published var error: String?
    @Published var plan: HistoryPlan?
    @Published private(set) var operationRecords: [GitOperationRecord] = []
    @Published var hasMore = false
    @Published private(set) var references: [Ref] = []
    @Published private(set) var selectedReference: String?
    @Published private(set) var searchText = ""
    @Published private(set) var searchField: GitHistorySearchField = .message
    @Published private(set) var searching = false
    @Published private(set) var searchLimitReached = false
    @Published private(set) var scrollTarget: String?
    @Published private(set) var comparisonBase: String?
    @Published private(set) var comparisonBaseLabel = ""
    @Published private(set) var explicitComparison: GitComparison?
    @Published private(set) var selectedParent: String?
    @Published private(set) var selectionSummary: GitSelectionSummary?
    @Published private(set) var selectionAnalysisError: String?
    @Published private(set) var resolvingComparison = false
    private var inspectionTask: Task<Void, Never>?
    private var inspectionGeneration = UUID()
    private var comparisonTask: Task<Void, Never>?
    private var comparisonGeneration = UUID()
    private var nextSkip: Int?
    private var searchGeneration = UUID()
    private var searchTask: Task<Void, Never>?
    private static let maximumVisibleCommits = 2_000

    var hasSearch: Bool { !searchText.isEmpty }
    var unavailable: Bool { busy || searching || resolvingComparison }

    init(workspace: GitWorkspace, l10n: L10n) {
        self.workspace = workspace
        self.l10n = l10n
    }

    func updateLocalization() {
        l10n = L10n(language: ConfigStore.load(from: ConfigStore.defaultURL()).language)
    }

    var selectedCommit: Commit? { selection.count == 1 ? commits.first { selection.contains($0.id) } : nil }
    func text(_ key: String) -> String { l10n.text(key) }

    var selectedCommits: [Commit] { commits.filter { selection.contains($0.id) } }

    var comparison: GitComparison? {
        if let explicitComparison { return explicitComparison }
        guard let commit = selectedCommit else { return nil }
        return GitComparison(from: selectedParent ?? commit.parents.first, to: commit.id)
    }

    func blockedReason(for action: HistoryAction, ids: Set<String>? = nil) -> String? {
        let ids = ids ?? selection
        if unavailable { return "git.selectionAnalyzing" }
        if operation != nil { return "git.error.inProgress" }
        if ids.isEmpty { return "git.error.selection" }
        if snapshot?.status.isEmpty == false { return "git.error.dirty" }
        if snapshot?.branch.isEmpty != false { return "git.error.detached" }
        switch action {
        case .squash, .rebase, .reword, .drop:
            if action == .squash && ids.count < 2 { return "git.error.squashSelection" }
            if action == .reword && ids.count != 1 { return "git.error.selectOne" }
            // Context-menu targets may differ from the current selection. The
            // preview validates those targets; never reuse another row's summary.
            guard ids == selection else { return nil }
            guard let selectionSummary else {
                return selectionAnalysisError == nil ? "git.selectionAnalyzing" : "git.selectionAnalysisFailed"
            }
            return action == .squash ? selectionSummary.squashBlockedReason : selectionSummary.rebaseBlockedReason
        case .revert:
            return commits.contains { ids.contains($0.id) && $0.isMerge } ? "git.error.merge" : nil
        case .cherryPick:
            return commits.contains { ids.contains($0.id) && $0.isMerge } ? "git.error.cherryPickMerge" : nil
        case .reset:
            return ids.count == 1 ? nil : "git.error.selectOne"
        }
    }

    func navigate(to id: String) {
        guard !busy else { return }
        if commits.contains(where: { $0.id == id }) {
            cancelComparisonRead()
            explicitComparison = nil
            selectedParent = nil
            selection = [id]
            scrollTarget = id
        } else {
            searchText = id
            searchField = .sha
            loadHistory()
        }
    }

    func selectParent(_ parent: String) {
        guard selectedCommit?.parents.contains(parent) == true else { return }
        cancelComparisonRead()
        selectedParent = parent
        explicitComparison = nil
    }

    func setComparisonBase(_ commit: Commit) {
        guard !busy else { return }
        cancelComparisonRead()
        comparisonBase = commit.id
        comparisonBaseLabel = commit.summary
    }

    func clearComparisonBase() {
        cancelComparisonRead()
        comparisonBase = nil
        comparisonBaseLabel = ""
    }

    func compare(to commit: Commit) {
        guard !busy, let base = comparisonBase else { return }
        cancelComparisonRead()
        selection = [commit.id]
        explicitComparison = GitComparison(from: base, to: commit.id)
    }

    func setComparisonBase(reference: Ref) async { await resolveComparisonReference(reference, asBase: true) }
    func compare(toReference reference: Ref) async {
        guard comparisonBase != nil else { return }
        await resolveComparisonReference(reference, asBase: false)
    }

    private func resolveComparisonReference(_ reference: Ref, asBase: Bool) async {
        guard !busy, !searching else { return }
        cancelComparisonRead()
        let generation = comparisonGeneration
        let base = comparisonBase
        let workspace = workspace
        resolvingComparison = true
        error = nil
        let task = Task { [weak self] in
            do {
                let id = try await workspace.commitID(forReference: reference.id)
                try Task.checkCancellation()
                guard let self, self.comparisonGeneration == generation else { return }
                self.resolvingComparison = false
                if asBase {
                    self.comparisonBase = id
                    self.comparisonBaseLabel = reference.name
                } else if let base {
                    self.selection = []
                    self.explicitComparison = GitComparison(from: base, to: id)
                }
            } catch {
                guard let self, self.comparisonGeneration == generation else { return }
                self.resolvingComparison = false
                if !(error is CancellationError) { self.report(error) }
            }
        }
        comparisonTask = task
        await task.value
    }

    func swapComparison() {
        guard !busy, let comparison else { return }
        cancelComparisonRead()
        explicitComparison = comparison.swapped()
    }

    func endComparison() {
        cancelComparisonRead()
        let target: String?
        if let comparison { target = comparison.reversed ? comparison.from : comparison.to }
        else { target = nil }
        explicitComparison = nil
        if selection.count == 2, let target { selection = [target] }
    }

    private func cancelComparisonRead() {
        comparisonTask?.cancel()
        comparisonTask = nil
        comparisonGeneration = UUID()
        resolvingComparison = false
    }

    func cancelInspection() {
        cancelComparisonRead()
        inspectionTask?.cancel()
        inspectionTask = nil
        inspectionGeneration = UUID()
    }

    private func inspectSelection() {
        cancelInspection()
        explicitComparison = nil
        selectedParent = nil
        selectionSummary = nil
        selectionAnalysisError = nil
        let selected = selectedCommits
        if selected.count == 2 {
            explicitComparison = GitComparison(from: selected[1].id, to: selected[0].id)
        }
        guard !selected.isEmpty else { return }
        let workspace = workspace
        let generation = inspectionGeneration
        inspectionTask = Task { [weak self] in
            do {
                let summary = try await workspace.selectionSummary(for: selected)
                try Task.checkCancellation()
                guard let self, self.inspectionGeneration == generation else { return }
                self.selectionSummary = summary
            } catch {
                guard let self, self.inspectionGeneration == generation, !(error is CancellationError) else { return }
                self.selectionAnalysisError = (error as? WorkspaceFailure).map { self.text($0.key) } ?? error.localizedDescription
            }
        }
    }

    func refresh(more: Bool = false) async {
        guard !unavailable else { return }
        if more {
            guard hasMore else { return }
            await loadHistory(more: true).value
            return
        }
        busy = true
        error = nil
        do { try await reload() } catch { report(error) }
        busy = false
    }

    func browse(reference: String?) async {
        guard !busy, selectedReference != reference else { return }
        selectedReference = reference
        selection = []
        await loadHistory().value
    }

    func search(text: String, field: GitHistorySearchField) {
        guard !busy else { return }
        searchText = text
        searchField = field
        selection = []
        loadHistory(debounce: true)
    }

    func clearSearch() {
        guard !busy else { return }
        searchText = ""
        searchField = .message
        loadHistory()
    }

    func locateHEAD() {
        guard !busy, let head = snapshot?.head, !head.isEmpty else { return }
        searchText = head
        searchField = .sha
        loadHistory()
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration = UUID()
        searching = false
    }

    private func reload() async throws {
        operation = try await workspace.operation()
        conflicts = try await workspace.conflicts()
        snapshot = try await workspace.snapshot()
        canSkipEmptyCherryPick = operation == .cherryPick ? try await workspace.canSkipEmptyCherryPick() : false
        references = try await workspace.references()
        await loadHistory(clearError: false, preserveComparison: true).value
    }

    @discardableResult
    private func loadHistory(more: Bool = false, debounce: Bool = false, clearError: Bool = true, preserveComparison: Bool = false) -> Task<Void, Never> {
        cancelComparisonRead()
        cancelSearch()
        let generation = searchGeneration
        let query = GitHistoryQuery(text: searchText, field: searchField, reference: selectedReference)
        let skip = more ? nextSkip ?? 0 : 0
        let retainedSelection = selection
        let retainedComparison = (preserveComparison || more) ? explicitComparison : nil
        let retainedParent = (preserveComparison || more) ? selectedParent : nil
        let workspace = workspace
        searching = true
        if clearError { error = nil }
        if !more {
            selection = []
            explicitComparison = retainedComparison
            selectedParent = retainedParent
            scrollTarget = nil
            commits = []
            graph = .empty
            hasMore = false
            nextSkip = nil
            searchLimitReached = false
        }
        // Do not retain a closed window's model while Git is reading. A newer
        // query cancels the process; the generation also rejects late responses.
        let task = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(250)) }
                let page = try await workspace.searchHistory(query, skip: skip)
                try Task.checkCancellation()
                guard let self, self.searchGeneration == generation else { return }
                self.commits = more ? self.commits + page.commits : page.commits
                self.graph = GraphLayout.layout(self.commits)
                self.nextSkip = page.nextSkip
                self.searchLimitReached = page.nextSkip != nil && self.commits.count >= Self.maximumVisibleCommits
                self.hasMore = page.nextSkip != nil && !self.searchLimitReached
                self.selection = (more ? self.selection : retainedSelection).intersection(Set(self.commits.map(\.id)))
                if self.selection.isEmpty, retainedComparison == nil, let first = self.commits.first {
                    self.selection = [self.commits.first { $0.id == self.snapshot?.head }?.id ?? first.id]
                }
                if !more {
                    if let retainedComparison { self.explicitComparison = retainedComparison }
                    if let retainedParent, self.selectedCommit?.parents.contains(retainedParent) == true {
                        self.selectedParent = retainedParent
                    }
                    self.scrollTarget = self.selection.first
                }
                self.searching = false
            } catch {
                guard let self, self.searchGeneration == generation else { return }
                self.searching = false
                if !(error is CancellationError) { self.report(error) }
            }
        }
        searchTask = task
        return task
    }

    func prepare(_ action: HistoryAction, selection override: Set<String>? = nil) async {
        guard !unavailable else { return }
        busy = true
        error = nil
        do { plan = try await workspace.preview(action, selected: override ?? selection) }
        catch { report(error) }
        busy = false
    }

    func execute(_ plan: HistoryPlan) async {
        await mutate { try await self.workspace.execute(plan) }
    }

    func finish(abort: Bool) async {
        await mutate { try await self.workspace.finishOperation(abort: abort) }
    }

    func skipEmptyCherryPick() async {
        await mutate { try await self.workspace.skipEmptyCherryPick() }
    }

    func markResolved(_ path: String) async {
        await mutate { try await self.workspace.markResolved(path: path) }
    }

    func clearOperationRecords() async {
        guard !busy else { return }
        await workspace.clearOperationRecords()
        operationRecords = await workspace.operationRecords()
    }

    private func mutate(_ action: () async throws -> Void) async {
        guard !unavailable else { return }
        busy = true
        isMutating = true
        defer { isMutating = false }
        await GitBadgeService.shared.beginMutation()
        defer { GitBadgeService.shared.endMutation() }
        error = nil
        do { try await action() } catch { report(error) }
        operationRecords = await workspace.operationRecords()
        do { try await reload() } catch { report(error) }
        busy = false
    }

    private func report(_ error: Error) {
        self.error = (error as? WorkspaceFailure).map { l10n.text($0.key) } ?? error.localizedDescription
    }
}

/// Finder only sends a URL. Git execution and windows belong to the host app.
@MainActor
final class GitWindows: NSObject, NSWindowDelegate {
    static let shared = GitWindows()
    private var windows: [String: NSWindowController] = [:]

    func chooseRepository() {
        let l10n = L10n(language: ConfigStore.load(from: ConfigStore.defaultURL()).language)
        let panel = NSOpenPanel()
        panel.title = l10n.text("git.openRepository")
        panel.message = l10n.text("git.repositoryPathHint")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let key = windows.first(where: { $0.value.window === window })?.key else { return }
        (window.contentView as? NSHostingView<GitWorkspaceView>)?.rootView.model.cancelSearch()
        (window.contentView as? NSHostingView<GitWorkspaceView>)?.rootView.model.cancelInspection()
        windows.removeValue(forKey: key)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let view = sender.contentView as? NSHostingView<GitWorkspaceView>,
              view.rootView.model.isMutating else { return true }
        guard sender.attachedSheet == nil else { return false }
        let alert = NSAlert()
        alert.messageText = view.rootView.model.text("git.title")
        alert.informativeText = view.rootView.model.text("git.waitBeforeClosing")
        alert.beginSheetModal(for: sender)
        return false
    }

    func open(_ url: URL) {
        Task {
            let l10n = L10n(language: ConfigStore.load(from: ConfigStore.defaultURL()).language)
            do {
                let workspace = try await GitWorkspace.open(at: url)
                let key = workspace.root.resolvingSymlinksInPath().path
                if let controller = windows[key] {
                    controller.showWindow(nil)
                    controller.window?.makeKeyAndOrderFront(nil)
                } else {
                    let model = GitWorkspaceModel(workspace: workspace, l10n: l10n)
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                          backing: .buffered, defer: false)
                    window.title = workspace.root.lastPathComponent + " — " + l10n.text("git.title")
                    window.contentView = NSHostingView(rootView: GitWorkspaceView(model: model))
                    window.minSize = NSSize(width: 900, height: 620)
                    window.isReleasedWhenClosed = false
                    window.delegate = self
                    window.center()
                    let controller = NSWindowController(window: window)
                    windows[key] = controller
                    controller.showWindow(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                let alert = NSAlert()
                alert.messageText = l10n.text("git.title")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
