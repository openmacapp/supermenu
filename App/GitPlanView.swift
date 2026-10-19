import SwiftUI
import SuperMenuGit

struct GitPlanView: View {
    @ObservedObject var model: GitWorkspaceModel
    @State var plan: HistoryPlan
    @State private var acknowledged = false
    @Environment(\.dismiss) private var dismiss

    private var needsAcknowledgement: Bool {
        (plan.action != .revert && !plan.published.isEmpty) || (plan.action == .reset && plan.resetMode == .hard)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.text("git." + plan.action.rawValue)).font(.title2.bold())
            Text(plan.snapshot.branch + " · " + String(plan.snapshot.head.prefix(8)))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(model.text("git.effect." + plan.action.rawValue))
            Text(model.l10n.text("git.affected", plan.affected.count)).font(.headline)

            if plan.action == .rebase {
                replayEditor
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
            Text(model.text("git.previewDiff")).font(.headline)
            GitDiffText(text: plan.diff).frame(minHeight: 120, maxHeight: .infinity)
            if !plan.published.isEmpty, plan.action != .revert {
                Label(model.l10n.text("git.published", plan.published.count), systemImage: "exclamationmark.triangle")
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
                          (plan.action == .squash && plan.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(24).frame(width: 780, height: 720)
        .onChange(of: plan.resetMode) { _, _ in acknowledged = false }
    }

    private var replayEditor: some View {
        VStack(alignment: .leading) {
            Text(model.text("git.replayHelp")).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(plan.entries.indices, id: \.self) { index in
                        HStack(alignment: .top) {
                            VStack(spacing: 4) {
                                Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .disabled(index == 0)
                                Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .disabled(index == plan.entries.count - 1)
                            }.buttonStyle(.borderless)
                            Text(plan.entries[index].commit.shortID).font(.caption.monospaced())
                            TextField(model.text("git.message"), text: $plan.entries[index].message, axis: .vertical)
                                .lineLimit(1...3).textFieldStyle(.roundedBorder)
                            Toggle(model.text("git.combinePrevious"), isOn: $plan.entries[index].combineWithPrevious)
                                .disabled(index == 0).toggleStyle(.checkbox)
                        }
                    }
                }
            }.frame(height: 175)
        }
    }

    private func move(_ index: Int, by offset: Int) {
        plan.entries.swapAt(index, index + offset)
        plan.entries[0].combineWithPrevious = false
    }
}
