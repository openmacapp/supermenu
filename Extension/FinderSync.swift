import AppKit
import FinderSync
import Foundation

@objc(FinderSync)
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override var toolbarItemName: String { "超级右键" }

    override var toolbarItemToolTip: String { "复制路径，或用编辑器打开" }

    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: "超级右键")
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
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
        return MenuRenderer.menu(from: nodes, target: self, action: #selector(performCommand(_:)))
    }

    @objc func performCommand(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? String, let command = MenuCommand.parse(token) else { return }
        let controller = FIFinderSyncController.default()
        let context = MenuContext(
            kind: .items,
            targetedFolder: controller.targetedURL(),
            selection: controller.selectedItemURLs() ?? []
        )
        let config = ConfigStore.load(from: ConfigStore.defaultURL())
        CommandRunner.run(command, context: context, config: config, presentErrors: false)
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
