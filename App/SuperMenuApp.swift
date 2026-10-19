import FinderSync
import SwiftUI

@main
struct SuperMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("超级右键", id: "settings") {
            SettingsRootView()
        }
        .defaultSize(width: 820, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        MenuBarExtra("超级右键", systemImage: "contextualmenu.and.cursorarrow") {
            MenuBarMenu()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.servicesProvider = ServiceProvider.shared
        NSUpdateDynamicServices()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let snapshot = FinderBridge.snapshot()
        let config = ConfigStore.load(from: ConfigStore.defaultURL())
        let context = MenuContext(kind: .items, targetedFolder: snapshot.folder, selection: snapshot.selection)
        let nodes = MenuBuilder.build(
            context: context,
            config: config,
            installedBundleIDs: InstalledApps.bundleIDs(referencedBy: config)
        )
        if let error = snapshot.error {
            Text(error)
            Divider()
        }
        MenuNodeList(nodes: nodes, context: context, config: config)
        Divider()
        Button("打开设置…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        Button("退出超级右键") {
            NSApp.terminate(nil)
        }
    }
}

private struct MenuNodeList: View {
    let nodes: [MenuNode]
    let context: MenuContext
    let config: MenuConfig

    var body: some View {
        ForEach(nodes) { node in
            switch node.kind {
            case .separator:
                Divider()
            case .command(let command):
                Button(node.title) {
                    CommandRunner.run(command, context: context, config: config, presentErrors: true)
                }
                .disabled(!node.isEnabled)
            case .submenu(let children):
                Menu(node.title) {
                    MenuNodeList(nodes: children, context: context, config: config)
                }
            }
        }
    }
}
