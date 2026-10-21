import SwiftUI
import GitKit

/// Reference selection filters history; checkout remains an explicit external action.
struct GitReferencesSidebar: View {
    @ObservedObject var model: GitWorkspaceModel
    @State private var query = ""

    private var selection: Binding<String?> {
        Binding(get: { model.selectedReference ?? "" }, set: { value in
            guard let value else { return }
            Task { await model.browse(reference: value.isEmpty ? nil : value) }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.text("git.browseHistory")).font(.caption.bold()).padding(8)
            TextField(model.text("git.filterReferences"), text: $query)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 8).padding(.bottom, 6)
            List(selection: selection) {
                Label(model.text("git.allReferences"), systemImage: "point.3.connected.trianglepath.dotted")
                    .tag("")
                group(.localBranch, title: "git.localBranches", symbol: "arrow.triangle.branch")
                group(.remoteBranch, title: "git.remoteBranches", symbol: "network")
                group(.tag, title: "git.tags", symbol: "tag")
            }.listStyle(.sidebar).font(.system(size: 12)).disabled(model.busy)
            if let id = model.selectedReference {
                Text(model.references.first { $0.id == id }?.name ?? id)
                    .font(.caption.monospaced()).lineLimit(2).textSelection(.enabled).padding(.horizontal, 8)
            }
            Text(model.text("git.browseOnly"))
                .font(.caption2).foregroundStyle(.secondary).padding(8)
        }
    }

    private func group(_ kind: Ref.Kind, title: String, symbol: String) -> some View {
        Section(model.text(title)) {
            ForEach(model.references.filter { $0.kind == kind &&
                (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { reference in
                HStack(spacing: 5) {
                    Image(systemName: symbol).foregroundStyle(.secondary)
                    Text(reference.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if reference.isHead {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            .accessibilityLabel(model.text("git.checkedOutBranch"))
                    }
                }.tag(reference.id)
                    .contextMenu {
                        Button(model.text("git.setComparisonBase")) { Task { await model.setComparisonBase(reference: reference) } }
                            .disabled(model.searching)
                        Button(model.text("git.compareWithBase")) { Task { await model.compare(toReference: reference) } }
                            .disabled(model.searching || model.comparisonBase == nil)
                    }
                    .help(reference.name + (reference.isHead ? " — " + model.text("git.checkedOutBranch") : ""))
            }
        }
    }
}
