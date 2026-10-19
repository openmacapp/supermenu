import XCTest
@testable import SuperMenuCore

final class LocalizationTests: XCTestCase {
    func testSystemLanguageMatchesRegionsAndFallsBackToEnglish() {
        let cases: [([String], AppLanguage)] = [
            (["ja-JP", "en-US"], .japanese), (["ko_KR"], .korean),
            (["zh-Hans-CN"], .chinese), (["fr-FR", "en-GB"], .english),
            (["de-DE", "ko-KR"], .korean), ([], .english)
        ]
        for (preferred, expected) in cases {
            XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: preferred), expected)
        }
        XCTAssertEqual(AppLanguage.japanese.resolved(preferredLanguages: ["en-US"]), .japanese)
    }

    func testOldAndFutureConfigLanguagesPreserveOtherSettings() throws {
        for json in ["{\"copyAbsolute\":false}", "{\"language\":\"future\",\"copyAbsolute\":false}"] {
            let config = try JSONDecoder().decode(MenuConfig.self, from: Data(json.utf8))
            XCTAssertEqual(config.language, .system)
            XCTAssertFalse(config.copyAbsolute)
            XCTAssertTrue(config.copyRelative)
        }
        var config = MenuConfig.standard
        config.language = .korean
        config.extraRoots = ["/tmp/project"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ConfigStore.save(config, to: url)
        XCTAssertEqual(ConfigStore.load(from: url), config)
    }

    func testExistingBuiltInTitlesTranslateWithoutChangingCustomNames() {
        let l10n = L10n(language: .japanese)
        var target = MenuConfig.standard.sendTargets[0]
        XCTAssertEqual(l10n.title(for: target), "デスクトップ")
        target.title = "My Desktop"
        XCTAssertEqual(l10n.title(for: target), "My Desktop")
        target.title = "桌面"
        target.isBuiltIn = false
        XCTAssertEqual(l10n.title(for: target), "桌面")
        var template = MenuConfig.standard.newFileTypes[0]
        XCTAssertEqual(l10n.title(for: template), "テキストファイル")
        template.title = "My Notes"
        XCTAssertEqual(l10n.title(for: template), "My Notes")
    }

    func testEveryLanguageHasCompleteResourcesAndMatchingPlaceholders() throws {
        func strings(_ language: AppLanguage) throws -> [String: String] {
            let url = try XCTUnwrap(L10n.resourceBundle.url(
                forResource: "Localizable", withExtension: "strings", subdirectory: nil,
                localization: language.rawValue
            ))
            let data = try Data(contentsOf: url)
            let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            let keyPattern = try NSRegularExpression(pattern: #"(?m)^"[^"]+"\s*="#)
            let entryCount = keyPattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            XCTAssertEqual(entryCount, values.count, "Duplicate localization keys in \(language)")
            return values
        }
        let english = try strings(.english)
        XCTAssertFalse(english.isEmpty)
        for language in AppLanguage.allCases where language != .system {
            let translations = try strings(language)
            XCTAssertEqual(Set(translations.keys), Set(english.keys), language.rawValue)
            for (key, value) in translations {
                XCTAssertFalse(value.isEmpty, "\(language): \(key)")
                XCTAssertEqual(value.filter { $0 == "%" }.count, english[key]?.filter { $0 == "%" }.count, key)
                XCTAssertEqual(L10n(language: language).text(key), value, key)
            }
        }
    }

    func testLocalizedNewFilesKeepContentsAndAvoidCollisions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cases: [(AppLanguage, String)] = [
            (.chinese, "未命名"), (.english, "Untitled"), (.japanese, "名称未設定"), (.korean, "제목 없음")
        ]
        let template = MenuConfig.standard.newFileTypes[2]
        for (language, stem) in cases {
            let l10n = L10n(language: language)
            let first = try FileActions.createFile(template: template, in: root, localization: l10n)
            let second = try FileActions.createFile(template: template, in: root, localization: l10n)
            XCTAssertEqual(first.lastPathComponent, "\(stem).json")
            XCTAssertEqual(second.lastPathComponent, "\(stem) 2.json")
            XCTAssertEqual(try String(contentsOf: first), "{}\n")
        }
        XCTAssertThrowsError(try FileActions.hash(of: root, algorithm: .sha256, localization: L10n(language: .english))) {
            XCTAssertEqual(($0 as? ActionError)?.message, "Checksums can only be calculated for files.")
        }
    }

    func testSavedLanguageChangesMenuWithoutChangingCommandIdentity() throws {
        let context = MenuContext(kind: .container, targetedFolder: URL(fileURLWithPath: "/tmp"), selection: [])
        let cases = [
            ("zh-Hans", "复制绝对路径"), ("en", "Copy Absolute Path"),
            ("ja", "絶対パスをコピー"), ("ko", "절대 경로 복사")
        ]
        for (language, expected) in cases {
            let config = try JSONDecoder().decode(MenuConfig.self, from: Data("{\"language\":\"\(language)\"}".utf8))
            let nodes = MenuBuilder.build(context: context, config: config, installedBundleIDs: [])
            guard case .submenu(let children) = nodes.first?.kind else { return XCTFail("Missing copy group") }
            XCTAssertEqual(children.first?.title, expected, language)
            XCTAssertEqual(children.first?.kind, .command(.builtin(.copyAbsolute)))
            XCTAssertEqual(children.first?.isEnabled, true)
        }
    }
}
