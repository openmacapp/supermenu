import FinderSync
import SwiftUI

@main
struct SuperMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = SettingsModel()

    var body: some Scene {
        Window(Text(model.l10n.text("app.name")), id: "settings") {
            SettingsRootView(model: model)
        }
        .defaultSize(width: 820, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                AboutButton(model: model)
            }
        }
        Window(Text(model.l10n.text("about.title", model.l10n.text("app.name"))), id: AboutView.windowID) {
            AboutView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        MenuBarExtra {
            MenuBarMenu(model: model)
        } label: {
            Image(nsImage: MenuIcons.menuBar)
                .accessibilityLabel(model.l10n.text("app.name"))
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
    @ObservedObject var model: SettingsModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let config = ConfigStore.load(from: ConfigStore.defaultURL())
        let l10n = L10n(language: config.language)
        let snapshot = FinderBridge.snapshot(localization: l10n)
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
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        } label: {
            Label(l10n.text("settings.open"), systemImage: "gearshape")
        }
        AboutButton(model: model)
        Button(l10n.text("app.quit")) {
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
                Button {
                    CommandRunner.run(command, context: context, config: config, presentErrors: true)
                } label: {
                    nodeLabel(node)
                }
                .disabled(!node.isEnabled)
            case .submenu(let children):
                Menu {
                    MenuNodeList(nodes: children, context: context, config: config)
                } label: {
                    nodeLabel(node)
                }
            }
        }
    }

    private func nodeLabel(_ node: MenuNode) -> some View {
        Label {
            Text(node.title)
        } icon: {
            if let image = MenuIcons.image(for: node) {
                Image(nsImage: image)
                    .renderingMode(image.isTemplate ? .template : .original)
            }
        }
    }
}
