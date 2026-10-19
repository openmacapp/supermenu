import SwiftUI
import GitKit
import SuperMenuGit

struct GitWorkspaceView: View {
    @ObservedObject var model: GitWorkspaceModel
    @State private var confirmAbort = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let error = model.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.error = nil } label: { Image(systemName: "xmark") }
                }.padding(12).background(.orange.opacity(0.08))
            }
            if model.operation != nil { conflictPanel }
            HSplitView {
                history.frame(minWidth: 380)
                details.frame(minWidth: 380)
            }
            HStack {
                Text(model.text("git.selectionHint"))
                Spacer()
                Text(model.workspace.root.path).lineLimit(1).truncationMode(.middle)
            }.font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .environment(\.locale, model.l10n.locale)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .superMenuConfigurationChanged)) { _ in
            model.updateLocalization()
        }
        .onChange(of: model.selection) { _, _ in Task { await model.loadDetails() } }
        .sheet(item: $model.plan) { plan in GitPlanView(model: model, plan: plan) }
        .confirmationDialog(model.text("git.abortPrompt"), isPresented: $confirmAbort) {
            Button(model.text("git.abort"), role: .destructive) { Task { await model.finish(abort: true) } }
            Button(model.text("git.cancel"), role: .cancel) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
            Text(model.snapshot?.branch.isEmpty == false ? model.snapshot!.branch : model.text("git.detached"))
                .font(.headline)
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
            Button(model.text("git.squash")) { Task { await model.prepare(.squash) } }
                .disabled(model.selection.count < 2 || model.operation != nil || model.busy)
            Button(model.text("git.revert")) { Task { await model.prepare(.revert) } }
                .disabled(model.selection.isEmpty || model.operation != nil || model.busy)
            Menu(model.text("git.advanced")) {
                Button(model.text("git.rebase")) { Task { await model.prepare(.rebase) } }
                Button(model.text("git.reset")) { Task { await model.prepare(.reset) } }
                    .disabled(model.selection.count != 1)
            }.disabled(model.selection.isEmpty || model.operation != nil || model.busy)
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .help(model.text("git.refresh")).disabled(model.busy)
        }.padding(12)
    }

    private var history: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                ForEach(Array(zip(model.commits, model.graph.nodes)), id: \.0.id) { commit, node in
                    HStack(spacing: 8) {
                        CommitLaneView(node: node, selected: model.selection.contains(commit.id))
                            .frame(width: CGFloat(model.graph.width) * 14 + 14, height: 60)
                            .accessibilityLabel(commit.isMerge ? model.text("git.mergeCommit") : "")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(commit.summary).lineLimit(1)
                            HStack(spacing: 6) {
                                Text(commit.shortID).monospaced()
                                Text(commit.authorName).lineLimit(1)
                                Spacer()
                                Text(commit.authorDate, style: .date)
                            }.font(.caption).foregroundStyle(.secondary)
                            if !commit.refs.isEmpty {
                                Text(commit.refs.joined(separator: " · ")).font(.caption2).foregroundStyle(model.selection.contains(commit.id) ? Color.white : Color.accentColor).lineLimit(1)
                            }
                        }
                    }
                    .frame(height: 60)
                    .listRowSeparator(.hidden)
                    .tag(commit.id)
                    .contextMenu {
                        let ids = model.selection.contains(commit.id) ? model.selection : [commit.id]
                        Button(model.text("git.squash")) { Task { await model.prepare(.squash, selection: ids) } }
                            .disabled(ids.count < 2)
                        Button(model.text("git.revert")) { Task { await model.prepare(.revert, selection: ids) } }
                        Menu(model.text("git.advanced")) {
                            Button(model.text("git.rebase")) { Task { await model.prepare(.rebase, selection: ids) } }
                            Button(model.text("git.reset")) { Task { await model.prepare(.reset, selection: [commit.id]) } }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 8))
                }
            }.listStyle(.plain)
                .overlay { if model.commits.isEmpty && !model.busy { Text(model.text("git.empty")).foregroundStyle(.secondary) } }
            if model.hasMore {
                Button(model.text("git.more")) { Task { await model.refresh(more: true) } }
                    .disabled(model.busy).padding(8)
            }
        }
    }

    @ViewBuilder private var details: some View {
        if let commit = model.selectedCommit {
            VStack(alignment: .leading, spacing: 8) {
                Text(commit.summary).font(.headline).textSelection(.enabled)
                Text(commit.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                if !commit.body.isEmpty { Text(commit.body).lineLimit(3).textSelection(.enabled) }
                VSplitView {
                    List(model.files, selection: $model.selectedFile) { file in
                        HStack {
                            Text(file.path).lineLimit(1)
                            Spacer()
                            Text("+\(file.additions)").foregroundStyle(.green)
                            Text("−\(file.deletions)").foregroundStyle(.red)
                        }.font(.caption).tag(file.path)
                    }.frame(minHeight: 80, idealHeight: 130, maxHeight: 220)
                        .onChange(of: model.selectedFile) { _, path in
                            if let path { Task { await model.loadDiff(path: path) } }
                        }
                    GitDiffText(text: model.diff).frame(minHeight: 150)
                }
            }.padding(12)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.largeTitle)
                Text(model.text(model.selection.isEmpty ? "git.selectCommit" : "git.multiSelection"))
            }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var conflictPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.text("git.operationPaused")).font(.headline)
                Text(model.operation?.rawValue ?? "").font(.caption.monospaced())
                Spacer()
                Button(model.text("git.abort")) { confirmAbort = true }.disabled(model.busy)
                Button(model.text("git.continue")) { Task { await model.finish(abort: false) } }
                    .disabled(model.busy || !model.conflicts.isEmpty)
            }
            Text(model.text("git.conflictHelp")).font(.caption)
            ForEach(model.conflicts, id: \.self) { path in
                HStack {
                    Text(path).lineLimit(1)
                    Spacer()
                    Button(model.text("git.reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting([model.workspace.root.appendingPathComponent(path)])
                    }
                    Button(model.text("git.resolved")) { Task { await model.markResolved(path) } }.disabled(model.busy)
                }
            }
        }.padding(12).background(.orange.opacity(0.08))
    }
}

private struct CommitLaneView: View {
    let node: CommitNode
    let selected: Bool
    private let colors: [Color] = [.blue, .purple, .orange, .teal, .pink]
    var body: some View {
        Canvas { context, size in
            func point(_ lane: Int, _ y: CGFloat) -> CGPoint { CGPoint(x: CGFloat(lane) * 14 + 10, y: y) }
            func line(_ from: CGPoint, _ to: CGPoint, lane: Int) {
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(selected ? .white : colors[lane % colors.count]), lineWidth: 2)
            }
            let center = point(node.lane, size.height / 2)
            for lane in node.passThrough { line(point(lane, 0), point(lane, size.height), lane: lane) }
            for lane in node.incoming { line(point(lane, 0), center, lane: lane) }
            for lane in node.outgoing { line(center, point(lane, size.height), lane: lane) }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)),
                         with: .color(selected ? .white : colors[node.lane % colors.count]))
        }
    }
}

/// AppKit handles large diffs and text selection without creating a SwiftUI view per line.
struct GitDiffText: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textContainerInset = NSSize(width: 10, height: 10)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
        view.textColor = .labelColor
    }
}
