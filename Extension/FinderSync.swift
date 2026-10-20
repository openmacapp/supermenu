import AppKit
import FinderSync
import Foundation

@objc(FinderSync)
final class FinderSync: FIFinderSync {
    private let menuRenderer = MenuRenderer()
    private lazy var badges = FinderBadges()

    override init() {
        super.init()
        // Register images only after FIFinderSync creates its extension context.
        _ = badges
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func beginObservingDirectory(at url: URL) { badges.begin(url) }
    override func endObservingDirectory(at url: URL) { badges.end(url) }
    override func requestBadgeIdentifier(for url: URL) { badges.request(url) }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind != .toolbarItemMenu else { return nil }
        let controller = FIFinderSyncController.default()
        let context = MenuContext(
            kind: surface(for: menuKind),
            targetedFolder: controller.targetedURL(),
            selection: controller.selectedItemURLs() ?? []
        )
        let config = ConfigStore.load(from: ConfigStore.defaultURL())
        let nodes = MenuBuilder.build(
            context: context,
            config: config,
            installedBundleIDs: InstalledApps.bundleIDs(referencedBy: config)
        )
        let menu = menuRenderer.menu(from: nodes, target: self, action: #selector(performCommand(_:)))
        // Finder inserts the returned items directly into its context menu.
        guard !nodes.isEmpty else { return nil }
        let root = NSMenu()
        let item = NSMenuItem(title: L10n(language: config.language).text("app.name"), action: nil, keyEquivalent: "")
        item.image = MenuIcons.finderRoot
        item.submenu = menu
        root.addItem(item)
        return root
    }

    @objc func performCommand(_ sender: NSMenuItem) {
        guard let command = menuRenderer.command(for: sender) else { return }
        let controller = FIFinderSyncController.default()
        let context = MenuContext(
            kind: .items,
            targetedFolder: controller.targetedURL(),
            selection: controller.selectedItemURLs() ?? []
        )
        let config = ConfigStore.load(from: ConfigStore.defaultURL())
        CommandRunner.run(command, context: context, config: config, presentErrors: true)
    }

    private func surface(for menuKind: FIMenuKind) -> MenuSurface {
        switch menuKind {
        case .contextualMenuForItems:
            return .items
        case .contextualMenuForContainer:
            return .container
        case .contextualMenuForSidebar:
            return .sidebar
        case .toolbarItemMenu:
            return .toolbar
        @unknown default:
            return .items
        }
    }
}
