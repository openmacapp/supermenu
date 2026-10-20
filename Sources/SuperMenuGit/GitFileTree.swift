import Foundation

/// An index of changed paths, never a scan of the working directory.
/// Rows are flattened once so List can render lazily even for large changesets.
public struct GitFileTree: Sendable {
    public struct Row: Identifiable, Sendable {
        public var id: String { (file == nil ? "directory:" : "file:") + path }
        public let path: String
        public let depth: Int
        public let file: GitChangedFile?
        public var name: String { String(path.split(separator: "/").last ?? "") }
    }

    public let directories: Set<String>
    private let orderedRows: [Row]

    public init(files: [GitChangedFile]) {
        var directories = Set<String>()
        var children: [String: [Row]] = [:]
        for file in files {
            let parts = file.path.split(separator: "/").map(String.init)
            var parent = ""
            for (depth, name) in parts.dropLast().enumerated() {
                let path = parent.isEmpty ? name : parent + "/" + name
                if directories.insert(path).inserted {
                    children[parent, default: []].append(Row(path: path, depth: depth, file: nil))
                }
                parent = path
            }
            children[parent, default: []].append(Row(path: file.path, depth: max(0, parts.count - 1), file: file))
        }
        for key in Array(children.keys) {
            children[key]?.sort {
                if ($0.file == nil) != ($1.file == nil) { return $0.file == nil }
                return $0.path < $1.path
            }
        }
        var rows: [Row] = []
        var stack = Array((children[""] ?? []).reversed())
        while let row = stack.popLast() {
            rows.append(row)
            if row.file == nil { stack.append(contentsOf: (children[row.path] ?? []).reversed()) }
        }
        self.directories = directories
        orderedRows = rows
    }

    /// Search exposes matching descendants and their ancestors regardless of
    /// saved collapse state, including matches against a renamed file's old path.
    public func rows(collapsed: Set<String> = [], query: String = "") -> [Row] {
        if !query.isEmpty {
            var includedFiles = Set<String>()
            var includedDirectories = Set<String>()
            for row in orderedRows {
                guard let file = row.file,
                      file.path.localizedCaseInsensitiveContains(query) ||
                        (file.oldPath?.localizedCaseInsensitiveContains(query) ?? false) else { continue }
                includedFiles.insert(file.path)
                let parts = file.path.split(separator: "/").dropLast()
                var path = ""
                for part in parts {
                    path = path.isEmpty ? String(part) : path + "/" + part
                    includedDirectories.insert(path)
                }
            }
            return orderedRows.filter {
                $0.file == nil ? includedDirectories.contains($0.path) : includedFiles.contains($0.path)
            }
        }
        var hiddenBelow: Int?
        return orderedRows.filter { row in
            if let depth = hiddenBelow {
                if row.depth > depth { return false }
                hiddenBelow = nil
            }
            if row.file == nil && collapsed.contains(row.path) { hiddenBelow = row.depth }
            return true
        }
    }
}
