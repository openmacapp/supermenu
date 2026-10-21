import SwiftUI
import SuperMenuGit

struct GitPlanView: View {
    @ObservedObject var model: GitWorkspaceModel
    @State var plan: HistoryPlan
    @State private var acknowledged = false
    @Environment(\.dismiss) private var dismiss

    private var needsAcknowledgement: Bool {
        warnsAboutRewrite || dropsCommits || (plan.action == .reset && plan.resetMode == .hard)
    }

    private var editsReplay: Bool {
        [.rebase, .reword, .drop].contains(plan.action)
    }

    private var dropsCommits: Bool {
        editsReplay && plan.entries.contains { $0.action == .drop }
    }

    private var warnsAboutRewrite: Bool {
        plan.action != .revert && plan.action != .cherryPick && !plan.published.isEmpty
    }

    private var comparisons: [GitComparison] {
        guard plan.action == .cherryPick || editsReplay else { return plan.comparisons }
        return plan.entries.map {
            GitComparison(from: $0.commit.parents.first, to: $0.id,
                          title: (editsReplay ? model.text("git.replay.action." + $0.action.rawValue) + " · " : "") +
                            $0.commit.shortID + "  " + $0.commit.summary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.text("git." + plan.action.rawValue)).font(.title2.bold())
            Text(plan.snapshot.branch + " · " + String(plan.snapshot.head.prefix(8)))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            if plan.action == .cherryPick {
                Text(model.l10n.text("git.cherryPickTarget", plan.snapshot.branch)).font(.callout.bold())
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.text("git.effect." + plan.action.rawValue))
                    Text(model.l10n.text("git.affected", plan.affected.count)).font(.headline)

                    if editsReplay {
                        replayEditor
                    } else if plan.action == .cherryPick {
                        cherryPickEditor
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(plan.affected) { commit in
                                    Text(commit.shortID + "  " + commit.summary).font(.callout).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 100)
                    }

                    if plan.action == .squash {
                        Text(model.text("git.message")).font(.headline)
                        TextEditor(text: $plan.message).font(.body).frame(height: 90).border(.separator)
                    }
                    if plan.action == .reset {
                        Picker(model.text("git.resetMode"), selection: $plan.resetMode) {
                            ForEach(HistoryReset.allCases, id: \.self) { mode in
                                Text(model.text("git.reset." + mode.rawValue)).tag(mode)
                            }
                        }
                        Text(model.text("git.resetEffect." + plan.resetMode.rawValue)).font(.callout)
                    }
                    GitCommandView(model: model, plan: plan)
                    if let error = plan.replayValidationError {
                        Label(model.text(error), systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.red)
                    }
                    Text(model.l10n.text("git.commandPublished", plan.published.count))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 400)
            Text(model.text("git.previewDiff")).font(.headline)
            if editsReplay {
                Text(model.text("git.replay.originalPatches")).font(.caption).foregroundStyle(.secondary)
            }
            GitChangesView(workspace: model.workspace, comparisons: comparisons, l10n: model.l10n)
                .frame(minHeight: 200, maxHeight: .infinity)
            if warnsAboutRewrite {
                Label(model.l10n.text("git.published", plan.published.count), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout)
            }
            if dropsCommits {
                Label(model.text("git.replay.dropWarning"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout)
            }
            if needsAcknowledgement {
                Toggle(model.text("git.acknowledge"), isOn: $acknowledged)
            }
            HStack {
                Text(model.text("git.localOnly")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.text("git.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.text("git.execute")) {
                    let confirmed = plan
                    dismiss()
                    Task { await model.execute(confirmed) }
                }
                .buttonStyle(.borderedProminent)
                .disabled((needsAcknowledgement && !acknowledged) ||
                          plan.replayValidationError != nil)
            }
        }
        .padding(24).frame(width: 960, height: 760)
        .onChange(of: plan.resetMode) { _, _ in acknowledged = false }
        .onChange(of: plan.entries.flatMap { [$0.id, $0.action.rawValue, $0.message] }) { _, _ in
            acknowledged = false
        }
    }

    private var cherryPickEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.text("git.cherryPickOrderHelp")).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(plan.entries.indices, id: \.self) { index in
                        HStack {
                            Text("\(index + 1).").monospacedDigit().frame(width: 28, alignment: .trailing)
                            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0).help(model.text("git.cherryPickEarlier"))
                            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == plan.entries.count - 1).help(model.text("git.cherryPickLater"))
                            Text(plan.entries[index].commit.shortID).font(.caption.monospaced())
                            Text(plan.entries[index].commit.summary).lineLimit(1).textSelection(.enabled)
                        }.buttonStyle(.borderless)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 130)
        }
    }

    private var replayEditor: some View {
        let originalOrder = Dictionary(uniqueKeysWithValues: plan.affected.enumerated().map { ($0.element.id, $0.offset + 1) })
        return VStack(alignment: .leading) {
            Text(model.text("git.replayHelp")).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(plan.entries.indices, id: \.self) { index in
                        HStack(alignment: .top) {
                            VStack(spacing: 4) {
                                Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .disabled(index == 0)
                                    .help(model.text("git.replay.earlier"))
                                    .accessibilityLabel(model.text("git.replay.earlier"))
                                Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .disabled(index == plan.entries.count - 1)
                                    .help(model.text("git.replay.later"))
                                    .accessibilityLabel(model.text("git.replay.later"))
                            }.buttonStyle(.borderless)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(originalOrder[plan.entries[index].id] ?? 0) → \(index + 1)")
                                Text(plan.entries[index].commit.shortID)
                            }.font(.caption.monospaced()).frame(width: 74, alignment: .leading)
                            Picker(model.text("git.replay.action"), selection: $plan.entries[index].action) {
                                ForEach(ReplayAction.allCases, id: \.self) { action in
                                    Text(model.text("git.replay.action." + action.rawValue)).tag(action)
                                }
                            }.labelsHidden().frame(width: 200)
                            VStack(alignment: .leading, spacing: 3) {
                                if plan.entries[index].action.editsMessage {
                                    TextField(model.text("git.message"), text: $plan.entries[index].message, axis: .vertical)
                                        .lineLimit(1...3).textFieldStyle(.roundedBorder)
                                } else {
                                    Text(plan.entries[index].commit.summary).lineLimit(2).textSelection(.enabled)
                                }
                                Text(model.text("git.replay.help." + plan.entries[index].action.rawValue))
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }.frame(height: 175)
        }
    }

    private func move(_ index: Int, by offset: Int) {
        plan.entries.swapAt(index, index + offset)
    }
}
