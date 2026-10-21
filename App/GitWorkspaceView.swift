import SwiftUI
import GitKit
import SuperMenuGit

struct GitWorkspaceView: View {
    @ObservedObject var model: GitWorkspaceModel
    @State private var confirmAbort = false
    @State private var confirmSkip = false

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
                    HSplitView {
                        history.frame(minWidth: 380)
                        GitCommitInspector(model: model).frame(minWidth: 240, idealWidth: 280, maxWidth: 420)
                    }.frame(minHeight: 200, idealHeight: 330)
                    details.frame(minHeight: 220, idealHeight: 300)
                }.frame(minWidth: 680)
            }
            Divider()
            GitOperationLogView(model: model)
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
        .onDisappear { model.cancelSearch(); model.cancelInspection() }
        .sheet(item: $model.plan) { plan in GitPlanView(model: model, plan: plan) }
        .confirmationDialog(model.text("git.abortPrompt"), isPresented: $confirmAbort) {
            Button(model.text("git.abort"), role: .destructive) { Task { await model.finish(abort: true) } }
            Button(model.text("git.cancel"), role: .cancel) {}
        }
        .confirmationDialog(model.text("git.cherryPickSkipPrompt"), isPresented: $confirmSkip) {
            Button(model.text("git.skipCherryPick")) { Task { await model.skipEmptyCherryPick() } }
            Button(model.text("git.cancel"), role: .cancel) {}
        } message: {
            Text("git cherry-pick --skip")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { GitWindows.shared.chooseRepository() } label: {
                Label(model.text("git.openRepository"), systemImage: "folder")
            }
            Divider().frame(height: 16)
            Image(systemName: "arrow.triangle.branch")
            Text(model.snapshot?.branch.isEmpty == false ? model.snapshot!.branch : model.text("git.detached"))
                .font(.headline)
                .lineLimit(1).truncationMode(.middle)
                .help(model.text("git.checkedOutBranch"))
            Spacer()
            if model.unavailable { ProgressView().controlSize(.small) }
            Button(model.text("git.squash")) { Task { await model.prepare(.squash) } }
                .disabled(model.blockedReason(for: .squash) != nil)
                .help(model.text(model.blockedReason(for: .squash) ?? "git.squash"))
            Button(model.text("git.revert")) { Task { await model.prepare(.revert) } }
                .disabled(model.blockedReason(for: .revert) != nil)
            Menu(model.text("git.advanced")) {
                Button(model.text("git.reword")) { Task { await model.prepare(.reword) } }
                    .disabled(model.blockedReason(for: .reword) != nil)
                Button(model.text("git.drop")) { Task { await model.prepare(.drop) } }
                    .disabled(model.blockedReason(for: .drop) != nil)
                Button(model.text("git.cherryPick")) { Task { await model.prepare(.cherryPick) } }
                    .disabled(model.blockedReason(for: .cherryPick) != nil)
                Button(model.text("git.rebase")) { Task { await model.prepare(.rebase) } }
                    .disabled(model.blockedReason(for: .rebase) != nil)
                Button(model.text("git.reset")) { Task { await model.prepare(.reset) } }
                    .disabled(model.blockedReason(for: .reset) != nil)
            }.disabled(model.selection.isEmpty || model.operation != nil || model.unavailable)
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .help(model.text("git.refresh")).disabled(model.unavailable)
        }.controlSize(.small).padding(8)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            Picker(model.text("git.searchField"), selection: Binding(
                get: { model.searchField },
                set: { model.search(text: model.searchText, field: $0) }
            )) {
                Text(model.text("git.message")).tag(GitHistorySearchField.message)
                Text(model.text("git.author")).tag(GitHistorySearchField.author)
                Text("SHA").tag(GitHistorySearchField.sha)
            }.labelsHidden().frame(width: 100)
            TextField(model.text("git.searchHistory"), text: Binding(
                get: { model.searchText },
                set: { model.search(text: $0, field: model.searchField) }
            ))
            .textFieldStyle(.roundedBorder)
            .help(model.text("git.searchLiteralHint"))
            if model.hasSearch {
                Button { model.clearSearch() } label: { Image(systemName: "xmark.circle.fill") }
                    .help(model.text("git.clearSearch"))
            }
            Button { model.locateHEAD() } label: { Image(systemName: "scope") }
                .help(model.text("git.locateHEAD")).accessibilityLabel(model.text("git.locateHEAD"))
                .disabled(model.snapshot?.head.isEmpty != false)
            if model.selectedReference != nil {
                Button { Task { await model.browse(reference: nil) } } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }.help(model.text("git.allReferences") + " — " + model.text("git.searchAllHint"))
                    .accessibilityLabel(model.text("git.allReferences"))
            }
        }.controlSize(.small).font(.system(size: 12)).padding(6).disabled(model.busy)
    }

    private var graphWidth: CGFloat { model.hasSearch ? 40 : max(40, CGFloat(model.graph.width) * 14 + 14) }

    private var history: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                searchBar
                if model.hasSearch {
                    Text(model.text("git.searchResultsHint"))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.bottom, 4)
                }
                HStack(spacing: 8) {
                    Text(model.text("git.graph")).frame(width: graphWidth, alignment: .leading)
                    Text(model.text("git.message")).frame(maxWidth: .infinity, alignment: .leading)
                    if geometry.size.width > 720 { Text(model.text("git.author")).frame(width: 120, alignment: .leading) }
                    if geometry.size.width > 600 { Text(model.text("git.date")).frame(width: 95, alignment: .trailing) }
                    Text("SHA").frame(width: 65, alignment: .trailing)
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
                Divider()
                ScrollViewReader { reader in
                    List(selection: $model.selection) {
                        ForEach(Array(zip(model.commits, model.graph.nodes)), id: \.0.id) { commit, node in
                            HStack(spacing: 8) {
                                Group {
                                    if model.hasSearch {
                                        // Filtered neighbors need not be parent/child commits.
                                        Image(systemName: commit.isMerge ? "arrow.triangle.merge" : "circle.fill")
                                            .font(.system(size: 8)).foregroundStyle(Color.accentColor)
                                    } else {
                                        CommitLaneView(node: node, selected: model.selection.contains(commit.id))
                                    }
                                }.frame(width: graphWidth, height: 26)
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
                                if geometry.size.width > 720 {
                                    Text(commit.authorName).lineLimit(1).frame(width: 120, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                }
                                if geometry.size.width > 600 {
                                    Text(commit.authorDate, format: .dateTime.year().month(.twoDigits).day(.twoDigits)).lineLimit(1)
                                        .frame(width: 95, alignment: .trailing).foregroundStyle(.secondary)
                                }
                                Text(commit.shortID).font(.system(size: 11, design: .monospaced))
                                    .frame(width: 65, alignment: .trailing).foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12)).frame(height: 26)
                            .listRowSeparator(.hidden).tag(commit.id).id(commit.id)
                            .contextMenu {
                                let ids = model.selection.contains(commit.id) ? model.selection : [commit.id]
                                Button(model.text("git.copySHA")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(commit.id, forType: .string)
                                }
                                Button(model.text("git.setComparisonBase")) { model.setComparisonBase(commit) }
                                    .disabled(model.busy)
                                Button(model.text("git.compareWithBase")) { model.compare(to: commit) }
                                    .disabled(model.busy || model.comparisonBase == nil)
                                Divider()
                                Button(model.text("git.cherryPick")) { Task { await model.prepare(.cherryPick, selection: ids) } }
                                    .disabled(model.blockedReason(for: .cherryPick, ids: ids) != nil)
                                Button(model.text("git.squash")) { Task { await model.prepare(.squash, selection: ids) } }
                                    .disabled(model.blockedReason(for: .squash, ids: ids) != nil)
                                Button(model.text("git.revert")) { Task { await model.prepare(.revert, selection: ids) } }
                                    .disabled(model.blockedReason(for: .revert, ids: ids) != nil)
                                Menu(model.text("git.advanced")) {
                                    Button(model.text("git.reword")) { Task { await model.prepare(.reword, selection: ids) } }
                                        .disabled(model.blockedReason(for: .reword, ids: ids) != nil)
                                    Button(model.text("git.drop")) { Task { await model.prepare(.drop, selection: ids) } }
                                        .disabled(model.blockedReason(for: .drop, ids: ids) != nil)
                                    Button(model.text("git.rebase")) { Task { await model.prepare(.rebase, selection: ids) } }
                                        .disabled(model.blockedReason(for: .rebase, ids: ids) != nil)
                                    Button(model.text("git.reset")) { Task { await model.prepare(.reset, selection: [commit.id]) } }
                                        .disabled(model.blockedReason(for: .reset, ids: [commit.id]) != nil)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 8))
                        }
                    }.listStyle(.plain).environment(\.defaultMinListRowHeight, 26)
                        .overlay {
                            if model.commits.isEmpty && !model.unavailable && model.error == nil {
                                Text(model.text(model.hasSearch ? "git.searchEmpty" : "git.empty")).foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: model.scrollTarget) { _, target in
                            if let target { reader.scrollTo(target, anchor: .center) }
                        }
                }
                if model.searchLimitReached {
                    Text(model.text("git.searchLimitReached")).font(.caption).foregroundStyle(.secondary).padding(4)
                }
                if model.hasMore {
                    Button(model.text("git.more")) { Task { await model.refresh(more: true) } }
                        .disabled(model.unavailable).controlSize(.small).padding(4)
                }
            }
        }
    }


    @ViewBuilder private var details: some View {
        if let comparison = model.comparison {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    let source = comparison.reversed ? comparison.to : comparison.from
                    let target = comparison.reversed ? comparison.from : comparison.to
                    Text(model.text("git.endpointComparison")).font(.caption.bold())
                    Text(endpoint(source) + " → " + endpoint(target)).font(.caption.monospaced())
                        .lineLimit(1).help((source ?? model.text("git.emptyTree")) + " → " + (target ?? model.text("git.emptyTree")))
                    Spacer(minLength: 0)
                    Button { model.swapComparison() } label: { Image(systemName: "arrow.left.arrow.right") }
                        .help(model.text("git.swapComparison")).accessibilityLabel(model.text("git.swapComparison"))
                    if model.explicitComparison != nil {
                        Button(model.text("git.endComparison")) { model.endComparison() }
                    }
                }.controlSize(.small).padding(8).disabled(model.busy)
                Text(model.text("git.comparisonHint")).font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.bottom, 5)
                Divider()
                GitChangesView(workspace: model.workspace, comparisons: [comparison], l10n: model.l10n)
                    .id(comparison.id)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.title2)
                Text(model.text(model.selection.isEmpty ? "git.selectCommit" : "git.selectTwoForDiff"))
            }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func endpoint(_ id: String?) -> String {
        id.map { String($0.prefix(8)) } ?? model.text("git.emptyTree")
    }

    private var conflictPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.text("git.operationPaused")).font(.headline)
                Text(model.operation?.rawValue ?? "").font(.caption.monospaced())
                Spacer()
                Button(model.text("git.abort")) { confirmAbort = true }.disabled(model.unavailable)
                if model.canSkipEmptyCherryPick {
                    Button(model.text("git.skipCherryPick")) { confirmSkip = true }.disabled(model.unavailable)
                }
                Button(model.text("git.continue")) { Task { await model.finish(abort: false) } }
                    .disabled(model.unavailable || !model.conflicts.isEmpty || model.canSkipEmptyCherryPick)
            }
            Text(model.text(model.canSkipEmptyCherryPick ? "git.cherryPickEmptyHelp" : "git.conflictHelp")).font(.caption)
            ForEach(model.conflicts, id: \.self) { path in
                HStack {
                    Text(path).lineLimit(1)
                    Spacer()
                    Button(model.text("git.reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting([model.workspace.root.appendingPathComponent(path)])
                    }
                    Button(model.text("git.resolved")) { Task { await model.markResolved(path) } }.disabled(model.unavailable)
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
