import SwiftUI
import SuperMenuGit

/// Shared by history inspection and operation confirmation. Only the selected file
/// has a patch in memory; SwiftUI cancels the previous read when selection changes.
struct GitChangesView: View {
    let workspace: GitWorkspace
    let comparisons: [GitComparison]
    let l10n: L10n
    @State private var comparisonID: String?
    @State private var files: [GitChangedFile] = []
    @State private var selectedPath: String?
    @State private var query = ""
    @State private var preview: GitDiffPreview?
    @State private var loadingFiles = false
    @State private var loadingDiff = false
    @State private var error: String?

    private var comparison: GitComparison? {
        comparisons.first { $0.id == comparisonID } ?? comparisons.first
    }
    private var selectedFile: GitChangedFile? { files.first { $0.path == selectedPath } }
    private var visibleFiles: [GitChangedFile] {
        query.isEmpty ? files : files.filter { $0.path.localizedCaseInsensitiveContains(query) ||
            ($0.oldPath?.localizedCaseInsensitiveContains(query) ?? false) }
    }
    private var requestID: String { (comparison?.id ?? "") + "\0" + (selectedPath ?? "") }

    var body: some View {
        VStack(spacing: 0) {
            if comparisons.count > 1 {
                Picker(l10n.text("git.previewCommit"), selection: Binding(
                    get: { comparison?.id ?? "" }, set: { comparisonID = $0 }
                )) {
                    ForEach(comparisons) { Text($0.title).tag($0.id) }
                }.padding(8)
                Divider()
            }
            HSplitView {
                fileList.frame(minWidth: 180, idealWidth: 250, maxWidth: 300)
                patch.frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: comparison?.id) { await loadFiles() }
        .task(id: requestID) { await loadPatch() }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(l10n.text("git.changedFiles", files.count)).font(.caption.bold())
                Spacer()
                if loadingFiles { ProgressView().controlSize(.mini) }
            }.padding(8)
            TextField(l10n.text("git.filterFiles"), text: $query)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 8).padding(.bottom, 6)
            List(visibleFiles, selection: $selectedPath) { file in
                HStack(spacing: 6) {
                    Text(file.status).font(.caption.monospaced().bold())
                        .foregroundStyle(statusColor(file.status)).frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((file.path as NSString).lastPathComponent).font(.system(size: 12))
                        let directory = (file.path as NSString).deletingLastPathComponent
                        if !directory.isEmpty { Text(directory).font(.system(size: 10)).foregroundStyle(.secondary) }
                    }.lineLimit(1).truncationMode(.middle)
                }.tag(file.path).help(file.oldPath.map { $0 + " → " + file.path } ?? file.path)
            }.listStyle(.plain)
                .overlay {
                    if !loadingFiles && visibleFiles.isEmpty {
                        Text(l10n.text(query.isEmpty ? "git.noChangedFiles" : "git.noMatchingFiles"))
                            .font(.caption).foregroundStyle(.secondary).padding()
                    }
                }
        }
    }

    private var patch: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                Text(selectedFile?.path ?? l10n.text("git.selectFile"))
                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 0)
                if loadingDiff { ProgressView().controlSize(.mini) }
            }.padding(8)
            Divider()
            if let error {
                Text(error).foregroundStyle(.orange).textSelection(.enabled).padding()
            }
            if let preview, !loadingDiff {
                if preview.truncated {
                    Label(l10n.text("git.diffLimited"), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).padding(8)
                }
                if preview.skippedLargeFile {
                    placeholder("git.largeFileDiff", symbol: "doc.badge.ellipsis")
                } else if preview.isBinary {
                    placeholder("git.binaryDiff", symbol: "doc.zipper")
                } else if preview.text.isEmpty {
                    placeholder("git.noTextChanges", symbol: "doc")
                } else {
                    GitDiffText(text: preview.text, identity: requestID)
                }
            } else {
                placeholder(loadingDiff ? "git.loadingDiff" : "git.selectFile", symbol: "text.alignleft")
            }
        }
    }

    private func placeholder(_ key: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2)
            Text(l10n.text(key)).font(.callout)
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "A": .green
        case "D": .red
        case "R", "C": .orange
        default: .secondary
        }
    }

    @MainActor private func loadFiles() async {
        files = []
        selectedPath = nil
        preview = nil
        query = ""
        error = nil
        loadingFiles = true
        guard let comparison else { loadingFiles = false; return }
        do {
            let result = try await workspace.changedFiles(in: comparison)
            try Task.checkCancellation()
            files = result
            selectedPath = result.first?.path
            loadingFiles = false
        } catch {
            guard !Task.isCancelled else { return }
            loadingFiles = false
            self.error = (error as? WorkspaceFailure).map { l10n.text($0.key) } ?? error.localizedDescription
        }
    }

    @MainActor private func loadPatch() async {
        preview = nil
        loadingDiff = false
        guard let comparison, let file = selectedFile else { return }
        loadingDiff = true
        error = nil
        do {
            let result = try await workspace.fileDiff(in: comparison, file: file)
            try Task.checkCancellation()
            preview = result
            loadingDiff = false
        } catch {
            guard !Task.isCancelled else { return }
            loadingDiff = false
            self.error = (error as? WorkspaceFailure).map { l10n.text($0.key) } ?? error.localizedDescription
        }
    }
}

/// TextKit draws the visible portion, supports selection/search and horizontal
/// scrolling. A bounded patch avoids building thousands of SwiftUI row views.
struct GitDiffText: NSViewRepresentable {
    let text: String
    var identity = ""
    var highlightDiff = true
    @Environment(\.colorScheme) private var colorScheme

    final class Coordinator {
        var identity = ""
        var text = ""
        var scheme: ColorScheme?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isRichText = false
        view.usesFindBar = true
        if highlightDiff {
            view.isHorizontallyResizable = true
            view.autoresizingMask = [.width]
            view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            view.textContainer?.widthTracksTextView = false
            view.textContainer?.containerSize = view.maxSize
        }
        view.textContainerInset = NSSize(width: 10, height: 8)
        scroll.hasHorizontalScroller = highlightDiff
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let cache = context.coordinator
        guard cache.text != text || cache.scheme != colorScheme || cache.identity != identity else { return }
        let resetScroll = cache.identity != identity
        cache.identity = identity
        cache.text = text
        cache.scheme = colorScheme
        view.textStorage?.setAttributedString(highlighted())
        if resetScroll {
            view.scrollToBeginningOfDocument(nil)
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func highlighted() -> NSAttributedString {
        let output = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        if !highlightDiff {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        }
        let hunkPattern = try! NSRegularExpression(pattern: #"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#)
        var oldLine = 0
        var newLine = 0
        var inHunk = false
        for line in text.components(separatedBy: "\n") {
            var color = NSColor.labelColor
            var background = NSColor.clear
            var oldNumber = ""
            var newNumber = ""
            let range = NSRange(line.startIndex..., in: line)
            if let match = hunkPattern.firstMatch(in: line, range: range) {
                let value = line as NSString
                oldLine = Int(value.substring(with: match.range(at: 1))) ?? 0
                newLine = Int(value.substring(with: match.range(at: 2))) ?? 0
                inHunk = true
                color = .systemBlue
                background = NSColor.systemBlue.withAlphaComponent(0.10)
            } else if line.hasPrefix("diff --git") {
                inHunk = false
                color = .secondaryLabelColor
            } else if inHunk && line.hasPrefix("+") {
                newNumber = String(newLine); newLine += 1
                color = colorScheme == .dark ? .systemGreen : NSColor(red: 0.10, green: 0.38, blue: 0.17, alpha: 1)
                background = NSColor.systemGreen.withAlphaComponent(0.12)
            } else if inHunk && line.hasPrefix("-") {
                oldNumber = String(oldLine); oldLine += 1
                color = colorScheme == .dark ? .systemRed : NSColor(red: 0.65, green: 0.12, blue: 0.13, alpha: 1)
                background = NSColor.systemRed.withAlphaComponent(0.12)
            } else if inHunk && line.hasPrefix(" ") {
                oldNumber = String(oldLine); oldLine += 1
                newNumber = String(newLine); newLine += 1
            } else {
                color = .secondaryLabelColor
            }
            let gutter = String(repeating: " ", count: max(0, 5 - oldNumber.count)) + oldNumber + " "
                + String(repeating: " ", count: max(0, 5 - newNumber.count)) + newNumber + "  │ "
            output.append(NSAttributedString(string: gutter, attributes: [
                .font: font, .foregroundColor: NSColor.secondaryLabelColor
            ]))
            output.append(NSAttributedString(string: line + "\n", attributes: [
                .font: font, .foregroundColor: color, .backgroundColor: background
            ]))
        }
        return output
    }
}
