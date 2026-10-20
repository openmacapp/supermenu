import SwiftUI
import GitKit
import SuperMenuGit

struct GitWorkspaceView: View {
    @ObservedObject var model: GitWorkspaceModel
    @State private var confirmAbort = false
    @State private var showCommitInfo = false

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
                GitReferencesSidebar(model: model)
                    .frame(minWidth: 150, idealWidth: 185, maxWidth: 280)
                VSplitView {
                    history.frame(minHeight: 170, idealHeight: 330)
                    details.frame(minHeight: 220, idealHeight: 300)
                }.frame(minWidth: 680)
            }
            HStack {
                Text(model.text("git.selectionHint"))
                Spacer()
                Text(model.workspace.root.path).lineLimit(1).truncationMode(.middle)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 5)
        }
        .environment(\.locale, model.l10n.locale)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .superMenuConfigurationChanged)) { _ in
            model.updateLocalization()
        }
        .sheet(item: $model.plan) { plan in GitPlanView(model: model, plan: plan) }
        .confirmationDialog(model.text("git.abortPrompt"), isPresented: $confirmAbort) {
            Button(model.text("git.abort"), role: .destructive) { Task { await model.finish(abort: true) } }
            Button(model.text("git.cancel"), role: .cancel) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
            Text(model.snapshot?.branch.isEmpty == false ? model.snapshot!.branch : model.text("git.detached"))
                .font(.headline)
                .help(model.text("git.checkedOutBranch"))
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
        }.controlSize(.small).padding(8)
    }

    private var graphWidth: CGFloat { max(40, CGFloat(model.graph.width) * 14 + 14) }

    private var history: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(model.text("git.graph")).frame(width: graphWidth, alignment: .leading)
                Text(model.text("git.message")).frame(maxWidth: .infinity, alignment: .leading)
                Text(model.text("git.author")).frame(width: 120, alignment: .leading)
                Text(model.text("git.date")).frame(width: 95, alignment: .trailing)
                Text("SHA").frame(width: 65, alignment: .trailing)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
            Divider()
            List(selection: $model.selection) {
                ForEach(Array(zip(model.commits, model.graph.nodes)), id: \.0.id) { commit, node in
                    HStack(spacing: 8) {
                        CommitLaneView(node: node, selected: model.selection.contains(commit.id))
                            .frame(width: graphWidth, height: 26)
                            .accessibilityLabel(commit.isMerge ? model.text("git.mergeCommit") : "")
                        HStack(spacing: 6) {
                            Text(commit.summary).lineLimit(1).help(commit.summary)
                            if !commit.refs.isEmpty {
                                Text(commit.refs.joined(separator: " · "))
                                    .font(.system(size: 10, weight: .medium)).lineLimit(1)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                    .help(commit.refs.joined(separator: "\n"))
                            }
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(commit.authorName).lineLimit(1).frame(width: 120, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(commit.authorDate, format: .dateTime.year().month(.twoDigits).day(.twoDigits)).lineLimit(1)
                            .frame(width: 95, alignment: .trailing).foregroundStyle(.secondary)
                        Text(commit.shortID).font(.system(size: 11, design: .monospaced))
                            .frame(width: 65, alignment: .trailing).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12)).frame(height: 26)
                    .listRowSeparator(.hidden).tag(commit.id)
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
            }.listStyle(.plain).environment(\.defaultMinListRowHeight, 26)
                .overlay { if model.commits.isEmpty && !model.busy { Text(model.text("git.empty")).foregroundStyle(.secondary) } }
            if model.hasMore {
                Button(model.text("git.more")) { Task { await model.refresh(more: true) } }
                    .disabled(model.busy).controlSize(.small).padding(4)
            }
        }
    }

    @ViewBuilder private var details: some View {
        if let commit = model.selectedCommit {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(commit.shortID).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(commit.summary).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .help(commit.summary + "\n\n" + commit.body).textSelection(.enabled)
                    Spacer()
                    Button { showCommitInfo = true } label: { Image(systemName: "info.circle") }
                        .buttonStyle(.borderless).help(model.text("git.commitDetails"))
                        .popover(isPresented: $showCommitInfo) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(commit.summary).font(.headline)
                                    Text(commit.id).font(.caption.monospaced())
                                    Text(commit.authorName + " · " + commit.authorDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if !commit.body.isEmpty { Text(commit.body) }
                                }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                            }.frame(width: 440, height: 280)
                        }
                    if commit.isMerge { Text(model.text("git.firstParent")).font(.caption).foregroundStyle(.secondary) }
                }.padding(8)
                Divider()
                GitChangesView(workspace: model.workspace,
                               comparisons: [GitComparison(from: commit.parents.first, to: commit.id)], l10n: model.l10n)
                    .id(commit.id)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.title2)
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
