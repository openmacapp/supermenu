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

    var title: String {
        switch self {
        case .enable: return "启用"
        case .menu: return "菜单"
        case .openWith: return "打开方式"
        case .paths: return "路径"
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
    @StateObject private var model = SettingsModel()
    @State private var page: SettingsPage? = .enable

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $page) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
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
        .frame(minWidth: 760, minHeight: 520)
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
                LabeledContent("访达扩展") {
                    Text(model.extensionEnabled ? "已启用" : "尚未启用")
                        .foregroundStyle(model.extensionEnabled ? .green : .secondary)
                }
                Button("打开访达扩展设置") {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
            } header: {
                Text("在访达里右键")
            } footer: {
                Text("启用后，选中文件或在窗口空白处右键，菜单出现在「超级右键」里。这是系统给访达扩展的位置。菜单栏图标现在就能对访达里选中的文件做同样的事，系统会先询问是否允许控制访达。")
            }

            Section("这版会做的事") {
                Text("复制绝对路径、相对路径和终端路径。相对路径默认相对 Git 仓库根，没有仓库时相对当前访达文件夹。")
                Text("用 Visual Studio Code、GoLand、Cursor、WorkBuddy 打开选中的文件或当前文件夹。没装的会显示为未安装。")
                Text("新建文本、Markdown、JSON、Swift、Go 文件，发送到桌面、文稿、下载，在终端或 iTerm 中打开，以及拷贝 MD5 / SHA256。")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct MenuPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("复制") {
                Toggle("复制绝对路径", isOn: model.binding(\.copyAbsolute))
                Toggle("复制相对路径", isOn: model.binding(\.copyRelative))
                Toggle("复制终端路径", isOn: model.binding(\.copyShell))
                Toggle("复制文件名", isOn: model.binding(\.copyName))
                Toggle("复制文件名（不含扩展名）", isOn: model.binding(\.copyStem))
            }
            Section("终端") {
                Toggle("在终端中打开", isOn: model.binding(\.terminal))
                Toggle("在 iTerm 中打开", isOn: model.binding(\.iTerm))
            }
            Section("新建") {
                ForEach(model.config.newFileTypes) { template in
                    Toggle(template.title, isOn: templateBinding(template.id))
                }
            }
            Section("发送到") {
                ForEach(model.config.sendTargets) { target in
                    Toggle(target.title, isOn: sendBinding(target.id))
                }
            }
            Section("其他") {
                Toggle("拷贝 MD5 和 SHA256", isOn: model.binding(\.hashes))
                Toggle("显示/隐藏", isOn: model.binding(\.toggleHidden))
                Toggle("按文件名新建文件夹", isOn: model.binding(\.folderFromName))
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
                        Text(model.isInstalled(app) ? "已安装" : "未安装")
                            .foregroundStyle(.secondary)
                        if !app.isBuiltIn {
                            Button {
                                model.config.openWith.removeAll { $0.id == app.id }
                                model.save()
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("移除")
                        }
                    }
                }
                Button("添加 App…") { pickingApp = true }
            } footer: {
                Text("右键「打开方式」会按这里的顺序出现。添加的 App 会和内置的 VS Code、GoLand、Cursor、WorkBuddy 用同一条命令。")
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
                Picker("相对路径基准", selection: relativeMode) {
                    Text("Git 仓库根").tag(RelativeAnchorMode.gitRoot)
                    Text("当前访达文件夹").tag(RelativeAnchorMode.finderFolder)
                }
            } footer: {
                Text("选中文件在仓库里时，复制相对路径会得到 src/main.go 这种路径。空白处右键则复制当前文件夹。找不到基准时改为绝对路径。")
            }
            Section {
                if model.config.extraRoots.isEmpty {
                    Text("还没有额外的项目根目录")
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
                    }
                }
                Button("添加项目根…") { pickingRoot = true }
            } header: {
                Text("优先使用的项目根")
            } footer: {
                Text("文件落在这些目录里时，相对路径以最长匹配的那个根为准，优先于 Git 仓库根。")
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
