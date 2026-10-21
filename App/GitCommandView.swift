import SwiftUI
import SuperMenuGit

/// Request identity prevents a slow preview from displaying commands for older
/// editor contents. The preview contains no execution or shell evaluation path.
struct GitCommandView: View {
    @ObservedObject var model: GitWorkspaceModel
    let plan: HistoryPlan
    @State private var expanded = false
    @State private var result: (request: Request, preview: GitCommandPreview)?
    @State private var failure: (request: Request, message: String)?

    private struct Request: Hashable {
        struct Entry: Hashable {
            let id: String
            let message: String
            let action: ReplayAction
        }
        let planID: UUID
        let mode: HistoryReset
        let message: String
        let entries: [Entry]

        init(_ plan: HistoryPlan) {
            planID = plan.id
            mode = plan.resetMode
            message = plan.message
            entries = plan.entries.map { Entry(id: $0.id, message: $0.message, action: $0.action) }
        }
    }

    var body: some View {
        let request = Request(plan)
        let preview = result.flatMap { $0.request == request ? $0.preview : nil }
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(model.text("git.commandPreview")).font(.headline)
                Spacer()
                Button {
                    guard let preview else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(preview.command, forType: .string)
                } label: {
                    Label(model.text("git.copyCommand"), systemImage: "doc.on.doc")
                }
                .disabled(preview == nil)
            }
            if let preview {
                ScrollView(.horizontal) {
                    Text(preview.command).font(.caption.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if !preview.files.isEmpty {
                    Text(model.text("git.commandReplayDependency")).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup(model.text("git.commandFiles"), isExpanded: $expanded) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                Text(model.text("git.commandPreparation")).font(.caption).foregroundStyle(.secondary)
                                Text(model.text("git.commandReplayHelp")).font(.caption).foregroundStyle(.secondary)
                                ForEach(preview.files) { file in
                                    Text(file.name).font(.caption.bold())
                                    Text(String(file.content.prefix(16_384))).font(.caption.monospaced()).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if file.content.count > 16_384 {
                                        Text(model.text("git.commandFileLimited")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 115)
                    }
                }
            } else if let failure, failure.request == request {
                Text(failure.message).font(.caption).foregroundStyle(.red)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(model.text("git.commandPreviewHelp")).font(.caption).foregroundStyle(.secondary)
        }
        .task(id: request) {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let preview = try await model.workspace.commandPreview(for: plan)
                try Task.checkCancellation()
                result = (request, preview)
                failure = nil
            } catch is CancellationError {
                // SwiftUI cancels the previous editor request on every change.
            } catch {
                guard !Task.isCancelled else { return }
                failure = (request, model.text((error as? WorkspaceFailure)?.key ?? "git.commandUnavailable"))
                result = nil
            }
        }
    }
}
