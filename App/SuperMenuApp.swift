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
            CommandMenu("Git") {
                Button(model.l10n.text("git.openRepository")) { GitWindows.shared.chooseRepository() }
                    .keyboardShortcut("o", modifiers: .command)
            }
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
        do { try GitBadgeService.shared.start(enabled: ConfigStore.load(from: ConfigStore.defaultURL()).gitBadgesEnabled) }
        catch { /* The existing app remains usable if the badge service cannot bind. */ }
        NotificationCenter.default.addObserver(forName: .superMenuConfigurationChanged, object: nil, queue: .main) { _ in
            GitBadgeService.shared.setEnabled(ConfigStore.load(from: ConfigStore.defaultURL()).gitBadgesEnabled)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            GitBadgeService.shared.invalidateAll()
        }
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let directory = GitLaunchURL.directory(from: url) {
                Task { @MainActor in GitWindows.shared.open(directory) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { GitBadgeService.shared.stop() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct MenuBarMenu: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let l10n = model.l10n
        Button {
            NSApp.activate(ignoringOtherApps: true)
            GitWindows.shared.chooseRepository()
        } label: {
            Label(l10n.text("git.openRepository"), systemImage: "arrow.triangle.branch")
        }
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
