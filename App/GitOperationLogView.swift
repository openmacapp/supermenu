import SwiftUI
import SuperMenuGit

struct GitOperationLogView: View {
    @ObservedObject var model: GitWorkspaceModel
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.text("git.log.scope")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.text("git.log.clear")) { Task { await model.clearOperationRecords() } }
                        .disabled(model.busy || model.operationRecords.isEmpty)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.operationRecords.reversed()) { record in
                            GitOperationRow(record: record, l10n: model.l10n)
                        }
                        if model.operationRecords.isEmpty {
                            Text(model.text("git.log.empty")).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 40, idealHeight: 120, maxHeight: 150)
            }.padding(.top, 4)
        } label: {
            HStack {
                Label(model.l10n.text("git.log.title", model.operationRecords.count), systemImage: "terminal")
                if let record = model.operationRecords.last {
                    Text(model.text("git." + record.action) + " · " + model.text("git.log." + record.status.rawValue))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }.font(.caption).controlSize(.small).padding(.horizontal, 10).padding(.vertical, 5)
    }
}

private struct GitOperationRow: View {
    let record: GitOperationRecord
    let l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(record.date, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
                Text(l10n.text("git." + record.action)).bold()
                Text(l10n.text("git.log." + record.status.rawValue))
                    .foregroundStyle(record.status == .succeeded ? Color.secondary : Color.orange)
                Text(l10n.text("git.log.duration", record.duration)).foregroundStyle(.secondary)
                if let code = record.exitCode {
                    Text(l10n.text(record.signalled ? "git.log.signal" : "git.log.exit", Int(code)))
                }
                Spacer()
                Button(l10n.text("git.log.copyDiagnostics")) { copy(diagnostics) }
            }
            if let command = record.command {
                HStack(alignment: .top) {
                    Text(command).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(l10n.text(record.commandModified ? "git.log.copyRedacted" : "git.copyCommand")) { copy(command) }
                }
                if record.commandModified {
                    Text(l10n.text("git.log.commandModified")).foregroundStyle(.secondary)
                }
            }
            if let key = record.failureKey { Text(l10n.text(key)).foregroundStyle(.orange) }
            if !record.stdout.isEmpty || !record.stderr.isEmpty || record.outputTruncated {
                DisclosureGroup(l10n.text("git.log.output")) {
                    VStack(alignment: .leading, spacing: 5) {
                        if !record.stdout.isEmpty { output(record.stdout, title: "stdout") }
                        if !record.stderr.isEmpty { output(record.stderr, title: "stderr") }
                        if record.outputTruncated { Text(l10n.text("git.log.truncated")).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
        }
    }

    private func output(_ text: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).bold()
            Text(text).font(.caption.monospaced()).textSelection(.enabled)
        }
    }

    /// Only display fields are copied. Raw process buffers never reach this view.
    private var diagnostics: String {
        [l10n.text("git.log.diagnosticHeader"), l10n.text("git." + record.action),
         l10n.text("git.log." + record.status.rawValue),
         l10n.text("git.log.duration", record.duration),
         record.exitCode.map { l10n.text(record.signalled ? "git.log.signal" : "git.log.exit", Int($0)) } ?? "",
         record.command ?? "", record.commandModified ? l10n.text("git.log.commandModified") : "",
         record.failureKey.map { l10n.text($0) } ?? "",
         "stdout:\n" + record.stdout, "stderr:\n" + record.stderr,
         record.outputTruncated ? l10n.text("git.log.truncated") : ""].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
