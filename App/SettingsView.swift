import AppKit
import FinderSync
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case enable
    case menu
    case openWith
    case paths

    var id: String { rawValue }

    func title(using l10n: L10n) -> String {
        switch self {
        case .enable: return l10n.text("settings.enable")
        case .menu: return l10n.text("settings.menu")
        case .openWith: return l10n.text("settings.openWith")
        case .paths: return l10n.text("settings.paths")
        }
    }

    var symbol: String {
        switch self {
        case .enable: return "power"
        case .menu: return "filemenu.and.selection"
        case .openWith: return "arrow.up.forward.app"
        case .paths: return "link"
        }
    }
}

final class SettingsModel: ObservableObject {
    @Published var config: MenuConfig
    @Published var extensionEnabled = false
    var l10n: L10n { L10n(language: config.language) }
    private let url: URL

    init() {
        url = ConfigStore.defaultURL()
        config = ConfigStore.load(from: url)
        refreshExtension()
    }

    func save() {
        do {
            try ConfigStore.save(config, to: url)
        } catch {
            NSSound.beep()
        }
    }

    func refreshExtension() {
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
    }

    func binding(_ keyPath: WritableKeyPath<MenuConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { self.config[keyPath: keyPath] = $0; self.save() }
        )
    }

    func isInstalled(_ app: OpenWithApp) -> Bool {
        InstalledApps.url(for: app.bundleIDs) != nil
    }
}

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel
    @State private var page: SettingsPage? = .enable

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(nsImage: MenuIcons.appIcon)
                        .resizable()
                        .frame(width: 42, height: 42)
                        .accessibilityHidden(true)
                    Text(model.l10n.text("app.name"))
                        .font(.headline)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                List(SettingsPage.allCases, selection: $page) { item in
                    Label(item.title(using: model.l10n), systemImage: item.symbol)
                        .tag(item)
                }
                .listStyle(.sidebar)

                AboutButton(model: model)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            switch page ?? .enable {
            case .enable:
                EnablePage(model: model)
            case .menu:
                MenuPage(model: model)
            case .openWith:
                OpenWithPage(model: model)
            case .paths:
                PathsPage(model: model)
            }
        }
        .frame(minWidth: 820, minHeight: 580)
        .environment(\.locale, model.l10n.locale)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshExtension()
        }
    }
}

private struct EnablePage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: MenuIcons.appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.l10n.text("app.name"))
                            .font(.title2.bold())
                        Text(model.l10n.text("app.tagline"))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(model.l10n.text("language.title"), selection: language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option == .system ? model.l10n.text("language.system") : option.nativeName)
                            .tag(option)
                    }
                }
            } footer: {
                Text(model.l10n.text("language.note"))
            }

            Section {
                LabeledContent(model.l10n.text("finder.extension")) {
                    Text(model.extensionEnabled ? model.l10n.text("status.enabled") : model.l10n.text("status.disabled"))
                        .foregroundStyle(model.extensionEnabled ? .green : .secondary)
                }
                Button(model.l10n.text("finder.settings")) {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
            } header: {
                Text(model.l10n.text("finder.heading"))
            } footer: {
                Text(model.l10n.text("finder.explanation"))
            }

            Section(model.l10n.text("features.heading")) {
                Text(model.l10n.text("features.paths"))
                Text(model.l10n.text("features.apps"))
                Text(model.l10n.text("features.files"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var language: Binding<AppLanguage> {
        Binding(
            get: { model.config.language },
            set: { model.config.language = $0; model.save() }
        )
    }
}

private struct MenuPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section(model.l10n.text("copy.heading")) {
                Toggle(model.l10n.text("copy.absolute"), isOn: model.binding(\.copyAbsolute))
                Toggle(model.l10n.text("copy.relative"), isOn: model.binding(\.copyRelative))
                Toggle(model.l10n.text("copy.shell"), isOn: model.binding(\.copyShell))
                Toggle(model.l10n.text("copy.name"), isOn: model.binding(\.copyName))
                Toggle(model.l10n.text("copy.stem"), isOn: model.binding(\.copyStem))
            }
            Section(model.l10n.text("terminal.heading")) {
                Toggle(model.l10n.text("open.terminal"), isOn: model.binding(\.terminal))
                Toggle(model.l10n.text("open.iterm"), isOn: model.binding(\.iTerm))
            }
            Section(model.l10n.text("new.heading")) {
                ForEach(model.config.newFileTypes) { template in
                    Toggle(model.l10n.title(for: template), isOn: templateBinding(template.id))
                }
            }
            Section(model.l10n.text("send.heading")) {
                ForEach(model.config.sendTargets) { target in
                    Toggle(model.l10n.title(for: target), isOn: sendBinding(target.id))
                }
            }
            Section(model.l10n.text("other.heading")) {
                Toggle(model.l10n.text("hash.both"), isOn: model.binding(\.hashes))
                Toggle(model.l10n.text("item.toggleHidden"), isOn: model.binding(\.toggleHidden))
                Toggle(model.l10n.text("item.folderFromName"), isOn: model.binding(\.folderFromName))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func templateBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.config.newFileTypes.first { $0.id == id }?.enabled ?? false },
            set: { newValue in
                guard let index = model.config.newFileTypes.firstIndex(where: { $0.id == id }) else { return }
                model.config.newFileTypes[index].enabled = newValue
                model.save()
            }
        )
    }

    private func sendBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.config.sendTargets.first { $0.id == id }?.enabled ?? false },
            set: { newValue in
                guard let index = model.config.sendTargets.firstIndex(where: { $0.id == id }) else { return }
                model.config.sendTargets[index].enabled = newValue
                model.save()
            }
        )
    }
}

private struct OpenWithPage: View {
    @ObservedObject var model: SettingsModel
    @State private var pickingApp = false

    var body: some View {
        Form {
            Section {
                ForEach(model.config.openWith) { app in
                    HStack {
                        Toggle(app.displayName, isOn: openBinding(app.id))
                        Spacer()
                        Text(model.isInstalled(app) ? model.l10n.text("status.installed") : model.l10n.text("status.notInstalled"))
                            .foregroundStyle(.secondary)
                        if !app.isBuiltIn {
                            Button {
                                model.config.openWith.removeAll { $0.id == app.id }
                                model.save()
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(model.l10n.text("action.remove"))
                            .accessibilityLabel(model.l10n.text("action.remove"))
                        }
                    }
                }
                Button(model.l10n.text("app.add")) { pickingApp = true }
            } footer: {
                Text(model.l10n.text("app.orderNote"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(isPresented: $pickingApp, allowedContentTypes: [.application]) { result in
            guard case .success(let url) = result else { return }
            addApp(at: url)
        }
    }

    private func openBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.config.openWith.first { $0.id == id }?.enabled ?? false },
            set: { newValue in
                guard let index = model.config.openWith.firstIndex(where: { $0.id == id }) else { return }
                model.config.openWith[index].enabled = newValue
                model.save()
            }
        )
    }

    private func addApp(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let bundleID = plist["CFBundleIdentifier"] as? String
        else {
            NSSound.beep()
            return
        }
        if model.config.openWith.contains(where: { $0.bundleIDs.contains(bundleID) }) { return }
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        model.config.openWith.append(
            OpenWithApp(bundleIDs: [bundleID], displayName: name, enabled: true, isBuiltIn: false)
        )
        model.save()
    }
}

private struct PathsPage: View {
    @ObservedObject var model: SettingsModel
    @State private var pickingRoot = false

    var body: some View {
        Form {
            Section {
                Picker(model.l10n.text("paths.anchor"), selection: relativeMode) {
                    Text(model.l10n.text("paths.gitRoot")).tag(RelativeAnchorMode.gitRoot)
                    Text(model.l10n.text("paths.finderFolder")).tag(RelativeAnchorMode.finderFolder)
                }
            } footer: {
                Text(model.l10n.text("paths.note"))
            }
            Section {
                if model.config.extraRoots.isEmpty {
                    Text(model.l10n.text("paths.empty"))
                        .foregroundStyle(.secondary)
                }
                ForEach(model.config.extraRoots, id: \.self) { root in
                    HStack {
                        Text(root)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            model.config.extraRoots.removeAll { $0 == root }
                            model.save()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(model.l10n.text("action.remove"))
                        .accessibilityLabel(model.l10n.text("action.remove"))
                    }
                }
                Button(model.l10n.text("paths.add")) { pickingRoot = true }
            } header: {
                Text(model.l10n.text("paths.roots"))
            } footer: {
                Text(model.l10n.text("paths.rootsNote"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(isPresented: $pickingRoot, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let path = url.standardizedFileURL.path
            if !model.config.extraRoots.contains(path) {
                model.config.extraRoots.append(path)
                model.save()
            }
        }
    }

    private var relativeMode: Binding<RelativeAnchorMode> {
        Binding(
            get: { model.config.relativeMode },
            set: { model.config.relativeMode = $0; model.save() }
        )
    }
}
