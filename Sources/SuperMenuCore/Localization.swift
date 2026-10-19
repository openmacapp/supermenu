import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case english = "en"

    public var id: String { rawValue }

    public var nativeName: String {
        switch self {
        case .system: return "System"
        case .chinese: return "简体中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            switch identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first {
            case "zh": return .chinese
            case "ja": return .japanese
            case "ko": return .korean
            case "en": return .english
            default: continue
            }
        }
        return .english
    }
}

public struct L10n {
    public let language: AppLanguage
    public var locale: Locale { Locale(identifier: language.rawValue) }
    private let bundle: Bundle
    private static let fallbackBundle = bundle(for: .english)

    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    public init(language: AppLanguage = .system, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.language = language.resolved(preferredLanguages: preferredLanguages)
        self.bundle = Self.bundle(for: self.language) ?? Self.resourceBundle
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        guard let path = resourceBundle.path(forResource: language.rawValue, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    public func text(_ key: String, _ arguments: CVarArg...) -> String {
        let fallback = Self.fallbackBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
        let format = bundle.localizedString(forKey: key, value: fallback, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }

    public func title(for template: NewFileTemplate) -> String {
        // Existing config files contain display titles; only translate the unchanged built-in name.
        if template.id == "txt", template.title == "文本文件" {
            return text("template.text")
        }
        return template.title
    }

    public func title(for target: SendTarget) -> String {
        guard target.isBuiltIn,
              let original = MenuConfig.standard.sendTargets.first(where: { $0.id == target.id }),
              target.title == original.title else { return target.title }
        return text("destination.\(target.id)")
    }
}
