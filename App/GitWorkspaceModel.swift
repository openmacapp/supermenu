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
    @Published var selection: Set<String> = []
    @Published var snapshot: RepositorySnapshot?
    @Published var files: [FileChange] = []
    @Published var diff = ""
    @Published var selectedFile: String?
    @Published var operation: InterruptedOperation?
    @Published var conflicts: [String] = []
    @Published var busy = false
    @Published var error: String?
    @Published var plan: HistoryPlan?
    @Published var hasMore = false
    private var limit = 200
    private var detailRequest = UUID()

    init(workspace: GitWorkspace, l10n: L10n) {
        self.workspace = workspace
        self.l10n = l10n
    }

    func updateLocalization() {
        l10n = L10n(language: ConfigStore.load(from: ConfigStore.defaultURL()).language)
    }

    var selectedCommit: Commit? { selection.count == 1 ? commits.first { selection.contains($0.id) } : nil }
    func text(_ key: String) -> String { l10n.text(key) }

    func refresh(more: Bool = false) async {
        guard !busy else { return }
        busy = true
        if more { limit += 200 }
        do { try await reload() } catch { report(error) }
        busy = false
    }

    private func reload() async throws {
        operation = try await workspace.operation()
        conflicts = try await workspace.conflicts()
        snapshot = try await workspace.snapshot()
        let page = try await workspace.history(limit: limit)
        commits = page.commits
        graph = GraphLayout.layout(commits)
        hasMore = page.nextSkip != nil
        selection.formIntersection(Set(commits.map(\.id)))
        await loadDetails()
    }

    func loadDetails() async {
        let request = UUID()
        detailRequest = request
        files = []
        diff = ""
        selectedFile = nil
        guard let commit = selectedCommit else { return }
        do {
            let changes = try await workspace.files(commit: commit.id)
            guard detailRequest == request else { return }
            files = changes
            if let path = changes.first?.path { await loadDiff(path: path) }
        } catch { if detailRequest == request { report(error) } }
    }

    func loadDiff(path: String) async {
        guard let commit = selectedCommit else { return }
        selectedFile = path
        do {
            let result = try await workspace.diff(commit: commit.id, path: path)
            guard selectedCommit?.id == commit.id, selectedFile == path else { return }
            diff = result
        } catch { report(error) }
    }

    func prepare(_ action: HistoryAction, selection override: Set<String>? = nil) async {
        guard !busy else { return }
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

    func markResolved(_ path: String) async {
        await mutate { try await self.workspace.markResolved(path: path) }
    }

    private func mutate(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        error = nil
        do { try await action() } catch { report(error) }
        do { try await reload() } catch { report(error) }
        busy = false
    }

    private func report(_ error: Error) {
        self.error = (error as? WorkspaceFailure).map { l10n.text($0.key) } ?? error.localizedDescription
    }
}

/// Finder only sends a URL. Git execution and windows belong to the host app.
@MainActor
final class GitWindows {
    static let shared = GitWindows()
    private var windows: [String: NSWindowController] = [:]

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
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
