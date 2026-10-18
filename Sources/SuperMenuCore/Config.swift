import Foundation

public enum RelativeAnchorMode: String, Codable, Equatable, CaseIterable {
    case gitRoot
    case finderFolder
}

public struct OpenWithApp: Codable, Equatable, Identifiable {
    public var bundleIDs: [String]
    public var displayName: String
    public var enabled: Bool
    public var isBuiltIn: Bool

    public var id: String { bundleIDs.joined(separator: "|") }

    public init(bundleIDs: [String], displayName: String, enabled: Bool, isBuiltIn: Bool) {
        self.bundleIDs = bundleIDs
        self.displayName = displayName
        self.enabled = enabled
        self.isBuiltIn = isBuiltIn
    }
}

public struct NewFileTemplate: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var ext: String
    public var contents: String
    public var enabled: Bool

    public init(id: String, title: String, ext: String, contents: String, enabled: Bool) {
        self.id = id
        self.title = title
        self.ext = ext
        self.contents = contents
        self.enabled = enabled
    }
}

public struct SendTarget: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var directory: String
    public var enabled: Bool
    public var isBuiltIn: Bool

    public init(id: String, title: String, directory: String, enabled: Bool, isBuiltIn: Bool) {
        self.id = id
        self.title = title
        self.directory = directory
        self.enabled = enabled
        self.isBuiltIn = isBuiltIn
    }
}

public struct MenuConfig: Codable, Equatable {
    public var copyAbsolute: Bool
    public var copyRelative: Bool
    public var copyShell: Bool
    public var copyName: Bool
    public var copyStem: Bool
    public var terminal: Bool
    public var iTerm: Bool
    public var hashes: Bool
    public var toggleHidden: Bool
    public var folderFromName: Bool
    public var relativeMode: RelativeAnchorMode
    public var extraRoots: [String]
    public var openWith: [OpenWithApp]
    public var newFileTypes: [NewFileTemplate]
    public var sendTargets: [SendTarget]

    public init(
        copyAbsolute: Bool,
        copyRelative: Bool,
        copyShell: Bool,
        copyName: Bool,
        copyStem: Bool,
        terminal: Bool,
        iTerm: Bool,
        hashes: Bool,
        toggleHidden: Bool,
        folderFromName: Bool,
        relativeMode: RelativeAnchorMode,
        extraRoots: [String],
        openWith: [OpenWithApp],
        newFileTypes: [NewFileTemplate],
        sendTargets: [SendTarget]
    ) {
        self.copyAbsolute = copyAbsolute
        self.copyRelative = copyRelative
        self.copyShell = copyShell
        self.copyName = copyName
        self.copyStem = copyStem
        self.terminal = terminal
        self.iTerm = iTerm
        self.hashes = hashes
        self.toggleHidden = toggleHidden
        self.folderFromName = folderFromName
        self.relativeMode = relativeMode
        self.extraRoots = extraRoots
        self.openWith = openWith
        self.newFileTypes = newFileTypes
        self.sendTargets = sendTargets
    }

    public static let standard = MenuConfig(
        copyAbsolute: true,
        copyRelative: true,
        copyShell: true,
        copyName: true,
        copyStem: true,
        terminal: true,
        iTerm: true,
        hashes: true,
        toggleHidden: true,
        folderFromName: true,
        relativeMode: .gitRoot,
        extraRoots: [],
        openWith: [
            OpenWithApp(bundleIDs: ["com.microsoft.VSCode"], displayName: "Visual Studio Code", enabled: true, isBuiltIn: true),
            OpenWithApp(bundleIDs: ["com.jetbrains.goland"], displayName: "GoLand", enabled: true, isBuiltIn: true),
            OpenWithApp(bundleIDs: ["com.todesktop.230313mzl4w4u92"], displayName: "Cursor", enabled: true, isBuiltIn: true),
            OpenWithApp(
                bundleIDs: ["com.tencent.workbuddy.mac", "com.workbuddy.workbuddy"],
                displayName: "WorkBuddy",
                enabled: true,
                isBuiltIn: true
            )
        ],
        newFileTypes: [
            NewFileTemplate(id: "txt", title: "文本文件", ext: "txt", contents: "", enabled: true),
            NewFileTemplate(id: "md", title: "Markdown", ext: "md", contents: "", enabled: true),
            NewFileTemplate(id: "json", title: "JSON", ext: "json", contents: "{}\n", enabled: true),
            NewFileTemplate(id: "swift", title: "Swift", ext: "swift", contents: "import Foundation\n\n", enabled: true),
            NewFileTemplate(id: "go", title: "Go", ext: "go", contents: "package main\n\nfunc main() {\n}\n", enabled: true)
        ],
        sendTargets: [
            SendTarget(id: "desktop", title: "桌面", directory: "~/Desktop", enabled: true, isBuiltIn: true),
            SendTarget(id: "documents", title: "文稿", directory: "~/Documents", enabled: true, isBuiltIn: true),
            SendTarget(id: "downloads", title: "下载", directory: "~/Downloads", enabled: true, isBuiltIn: true)
        ]
    )

    private enum CodingKeys: String, CodingKey {
        case copyAbsolute, copyRelative, copyShell, copyName, copyStem
        case terminal, iTerm, hashes, toggleHidden, folderFromName
        case relativeMode, extraRoots, openWith, newFileTypes, sendTargets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.standard
        copyAbsolute = try container.decodeIfPresent(Bool.self, forKey: .copyAbsolute) ?? fallback.copyAbsolute
        copyRelative = try container.decodeIfPresent(Bool.self, forKey: .copyRelative) ?? fallback.copyRelative
        copyShell = try container.decodeIfPresent(Bool.self, forKey: .copyShell) ?? fallback.copyShell
        copyName = try container.decodeIfPresent(Bool.self, forKey: .copyName) ?? fallback.copyName
        copyStem = try container.decodeIfPresent(Bool.self, forKey: .copyStem) ?? fallback.copyStem
        terminal = try container.decodeIfPresent(Bool.self, forKey: .terminal) ?? fallback.terminal
        iTerm = try container.decodeIfPresent(Bool.self, forKey: .iTerm) ?? fallback.iTerm
        hashes = try container.decodeIfPresent(Bool.self, forKey: .hashes) ?? fallback.hashes
        toggleHidden = try container.decodeIfPresent(Bool.self, forKey: .toggleHidden) ?? fallback.toggleHidden
        folderFromName = try container.decodeIfPresent(Bool.self, forKey: .folderFromName) ?? fallback.folderFromName
        relativeMode = try container.decodeIfPresent(RelativeAnchorMode.self, forKey: .relativeMode) ?? fallback.relativeMode
        extraRoots = try container.decodeIfPresent([String].self, forKey: .extraRoots) ?? fallback.extraRoots
        openWith = try container.decodeIfPresent([OpenWithApp].self, forKey: .openWith) ?? fallback.openWith
        newFileTypes = try container.decodeIfPresent([NewFileTemplate].self, forKey: .newFileTypes) ?? fallback.newFileTypes
        sendTargets = try container.decodeIfPresent([SendTarget].self, forKey: .sendTargets) ?? fallback.sendTargets
    }
}

public enum ConfigStore {
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SuperMenu/config.json")
    }

    public static func load(from url: URL) -> MenuConfig {
        guard let data = try? Data(contentsOf: url) else { return .standard }
        guard let config = try? JSONDecoder().decode(MenuConfig.self, from: data) else { return .standard }
        return config
    }

    public static func save(_ config: MenuConfig, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}
