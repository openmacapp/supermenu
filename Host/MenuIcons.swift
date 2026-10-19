import AppKit

/// Shared by the SwiftUI menu bar and the AppKit Finder extension.
enum MenuIcons {
    static let appIcon: NSImage = NSImage(named: "AppIcon") ?? NSImage(size: NSSize(width: 64, height: 64))

    static let menuBar: NSImage = {
        let image = NSImage(named: "MenuBarTemplate")
            ?? NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    static var finderRoot: NSImage? { templateSymbol("computermouse") }

    static func symbol(for node: MenuNode) -> String {
        switch node.kind {
        case .command(let command):
            switch command {
            case .builtin(let builtin):
                switch builtin {
                case .copyAbsolute: return "doc.on.doc"
                case .copyRelative: return "arrow.triangle.branch"
                case .copyShell: return "terminal"
                case .copyName, .copyStem: return "textformat.abc"
                case .openTerminal, .openITerm: return "terminal"
                case .hashMD5, .hashSHA256: return "number"
                case .toggleHidden: return "eye"
                case .folderFromName: return "folder.badge.plus"
                }
            case .openApp: return "arrow.up.forward.app"
            case .newFile: return "doc.badge.plus"
            case .sendCopy: return "doc.on.doc"
            case .sendMove: return "folder"
            }
        case .submenu:
            switch node.id {
            case "sub:copy": return "doc.on.doc"
            case "sub:open": return "arrow.up.forward.app"
            case "sub:new": return "doc.badge.plus"
            case "sub:send": return "square.and.arrow.up"
            case "sub:tools": return "wrench.and.screwdriver"
            default: return "folder"
            }
        case .separator:
            return ""
        }
    }

    static func image(for node: MenuNode) -> NSImage? {
        if let bundleIDs = applicationBundleIDs(for: node),
           let url = InstalledApps.url(for: bundleIDs),
           let image = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage {
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = false
            return image
        }
        return templateSymbol(symbol(for: node))
    }

    private static func templateSymbol(_ name: String) -> NSImage? {
        // Finder may serialize the image before displaying it. Give the symbol
        // an adaptive foreground color as well as its template flag.
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(hierarchicalColor: .labelColor))
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
    }

    private static func applicationBundleIDs(for node: MenuNode) -> [String]? {
        switch node.kind {
        case .command(.openApp(let bundleIDs)): return bundleIDs
        case .command(.builtin(.openTerminal)): return ["com.apple.Terminal"]
        case .command(.builtin(.openITerm)): return ["com.googlecode.iterm2"]
        default: return nil
        }
    }
}
