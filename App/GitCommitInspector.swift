import SwiftUI
import GitKit
import SuperMenuGit

/// Selection metadata stays visible while the shared file browser shows one diff.
struct GitCommitInspector: View {
    @ObservedObject var model: GitWorkspaceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let commit = model.selectedCommit {
                    commitDetails(commit)
                } else if !model.selection.isEmpty {
                    selectionDetails
                } else {
                    Text(model.text(model.explicitComparison == nil ? "git.selectCommit" : "git.comparisonHint"))
                        .foregroundStyle(.secondary)
                }
                if let base = model.comparisonBase {
                    Divider()
                    Text(model.text("git.comparisonBase")).font(.caption.bold())
                    Text(model.comparisonBaseLabel).lineLimit(2)
                    hashRow(base)
                    Button(model.text("git.clearComparisonBase")) { model.clearComparisonBase() }
                        .disabled(model.busy)
                }
            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }.background(.quaternary.opacity(0.2))
    }

    private func commitDetails(_ commit: Commit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(commit.summary.prefix(4096))).font(.system(size: 13, weight: .semibold)).textSelection(.enabled)
            hashRow(commit.id)
            Text(commit.authorName + " <" + commit.authorEmail + ">")
                .foregroundStyle(.secondary).textSelection(.enabled)
            Text(commit.authorDate.formatted(date: .abbreviated, time: .standard)).foregroundStyle(.secondary)
            if commit.committerName != commit.authorName || commit.committerEmail != commit.authorEmail {
                Text(model.text("git.committer") + ": " + commit.committerName + " <" + commit.committerEmail + ">")
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(model.text("git.committedAt") + ": " + commit.commitDate.formatted(date: .abbreviated, time: .standard))
                .foregroundStyle(.secondary)
            if !commit.body.isEmpty {
                Text(String(commit.body.prefix(16_384))).textSelection(.enabled)
            }
            if commit.summary.count > 4096 || commit.body.count > 16_384 {
                Text(model.text("git.messagePreviewLimited")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(model.text("git.setComparisonBase")) { model.setComparisonBase(commit) }
                Button(model.text("git.compareWithBase")) { model.compare(to: commit) }
                    .disabled(model.comparisonBase == nil)
            }.controlSize(.small).disabled(model.busy)
            if !commit.parents.isEmpty {
                Divider()
                ForEach(Array(commit.parents.enumerated()), id: \.element) { index, parent in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.l10n.text("git.parentNumber", index + 1)).font(.caption.bold())
                        Text(parent).font(.caption.monospaced()).textSelection(.enabled)
                        HStack {
                            Button(model.text("git.goToParent")) { model.navigate(to: parent) }
                            if commit.isMerge {
                                Button(model.text("git.compareParent")) { model.selectParent(parent) }
                                    .disabled((model.selectedParent ?? commit.parents.first) == parent && model.explicitComparison == nil)
                            }
                        }.controlSize(.small).disabled(model.busy)
                    }
                }
            }
        }
    }

    private var selectionDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.l10n.text("git.selectedCount", model.selection.count)).font(.headline)
            if let first = model.selectedCommits.last, let last = model.selectedCommits.first {
                Text(first.shortID + " … " + last.shortID).font(.caption.monospaced()).textSelection(.enabled)
            }
            if let summary = model.selectionSummary {
                Label(model.text(summary.isContiguous ? "git.selectionContiguous" : "git.selectionNotContiguous"),
                      systemImage: summary.isContiguous ? "link" : "link.badge.plus")
                Text(model.l10n.text("git.selectedMerges", summary.mergeCount))
                Text(model.text(membershipKey(summary.mainline)))
                operationReason(.squash, title: "git.squash")
                operationReason(.rebase, title: "git.rebase")
            } else if let error = model.selectionAnalysisError {
                Text(error).foregroundStyle(.orange)
            } else {
                ProgressView(model.text("git.selectionAnalyzing")).controlSize(.small)
            }
            Text(model.text("git.selectionPreviewHint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func operationReason(_ action: HistoryAction, title: String) -> some View {
        if let reason = model.blockedReason(for: action) {
            Text(model.text(title) + ": " + model.text(reason)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func membershipKey(_ membership: GitMainlineMembership) -> String {
        switch membership {
        case .all: "git.selectionOnMainline"
        case .notAll: "git.selectionOffMainline"
        case .unknown: "git.selectionAnalysisLimited"
        }
    }

    private func hashRow(_ id: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(id).font(.caption.monospaced()).textSelection(.enabled)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(id, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help(model.text("git.copySHA"))
                .accessibilityLabel(model.text("git.copySHA"))
        }
    }
}
