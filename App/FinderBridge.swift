import AppKit
import Foundation

struct FinderSnapshot {
    var folder: URL?
    var selection: [URL]
    var error: String?
}

enum FinderBridge {
    static func snapshot() -> FinderSnapshot {
        let source = """
        tell application "Finder"
          set recordSep to ASCII character 30
          set lineSep to ASCII character 10
          set folderPath to ""
          try
            set folderPath to POSIX path of (target of front Finder window as alias)
          end try
          set chunks to {}
          repeat with f in (selection as list)
            set end of chunks to POSIX path of (f as alias)
          end repeat
          set AppleScript's text item delimiters to lineSep
          set joined to chunks as text
          set AppleScript's text item delimiters to recordSep
          return folderPath & recordSep & joined
        end tell
        """
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return FinderSnapshot(folder: nil, selection: [], error: "无法查询访达")
        }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "访达没有响应。请在系统设置的自动化里允许超级右键控制访达。"
            return FinderSnapshot(folder: nil, selection: [], error: message)
        }
        let text = result.stringValue ?? ""
        let parts = text.components(separatedBy: "\u{1e}")
        let folderText = parts.first ?? ""
        let folder = folderText.isEmpty ? nil : URL(fileURLWithPath: folderText, isDirectory: true)
        let itemText = parts.dropFirst().first ?? ""
        let selection = itemText.split(separator: "\n", omittingEmptySubsequences: true).map {
            URL(fileURLWithPath: String($0))
        }
        return FinderSnapshot(folder: folder, selection: selection, error: nil)
    }
}
