import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class AppLocalizationSmokeTests: XCTestCase {
    func testSystemLanguageResolutionAndStableIdentifiers() {
        let cases: [(String, AppPreferences.Language)] = [
            ("ja-JP", .japanese), ("ko_KR", .korean), ("es-MX", .spanish),
            ("zh-TW", .traditionalChinese), ("zh-HK", .traditionalChinese),
            ("zh-Hant-CN", .traditionalChinese), ("zh-Hans-HK", .simplifiedChinese),
            ("zh-CN", .simplifiedChinese), ("en-GB", .english)]
        for (tag, expected) in cases { XCTAssertEqual(AppPreferences.Language.resolve(preferredLanguages: [tag]), expected) }
        XCTAssertEqual(AppPreferences.Language.resolve(preferredLanguages: ["fr-FR", "ko-KR"]), .korean)
        XCTAssertEqual(AppPreferences.Language.resolve(preferredLanguages: []), .english)
        XCTAssertEqual(AppPreferences.Language(rawValue: "simplifiedChinese"), .simplifiedChinese)
        XCTAssertEqual(AppPreferences.Language(rawValue: "english"), .english)
        XCTAssertEqual(Set(AppPreferences.Language.allCases.map(\.localeIdentifier)), ["zh-Hans", "en", "ja", "ko", "zh-Hant", "es"])
    }

    @MainActor func testLanguageChoiceSurvivesRestartWithoutChangingUserDefaults() {
        let suite = "AppLocalizationSmokeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for language in AppPreferences.Language.allCases {
            let preferences = AppPreferences(defaults: defaults)
            preferences.followsSystemLanguage = false
            preferences.customLanguage = language
            let restored = AppPreferences(defaults: defaults)
            XCTAssertEqual(restored.resolvedLanguage, language)
            XCTAssertEqual(restored.locale.identifier, language.localeIdentifier)
        }
    }

    func testAllNewLanguagesTranslateSettingsAndActivity() {
        let expected: [(AppPreferences.Language, String, String)] = [
            (.japanese, "設定", "作業中"), (.korean, "설정", "작업 중"),
            (.traditionalChinese, "設置", "工作中"), (.spanish, "Ajustes", "Trabajando")]
        for (language, settings, working) in expected {
            XCTAssertEqual(AppCopy(language: language).text("设置", "Settings"), settings)
            XCTAssertEqual(CodexActivityCopy(language: language).statusTitle(for: .working), working)
        }
    }

    func testInterpolationLocalizesTemplateWithoutTranslatingOrReinterpretingValues() {
        let value = "/tmp/用户{{1}}/한국어"
        let ko = AppCopy(language: .korean)
        XCTAssertEqual(ko.text("\(value) 个会话", "\(value) sessions"), "세션 \(value)개")
        let traditional = AppCopy(language: .traditionalChinese)
        XCTAssertEqual(traditional.text("打开 \(value)", "Open \(value)"), "打開 \(value)")
        let request = IslandDetailText("请在 \(value) 中确认。", "Confirm this request in \(value).")
        XCTAssertEqual(request.value(.spanish), "Confirma esta solicitud en \(value).")
        XCTAssertEqual(IslandDetailText("设置 {{0}}").value(.traditionalChinese), "设置 {{0}}")
        XCTAssertEqual(AppLocalization.text(chinese: "设置", english: "Settings", language: "ko_KR"), "설정")
        XCTAssertEqual(AppLocalization.text(chinese: "设置", english: "Settings", language: "zh_TW"), "設置")
        var streamed = IslandDetailText("旧消息", "Old message")
        streamed.chinese = value; streamed.english = value
        XCTAssertEqual(streamed.value(.japanese), value)
    }

    func testCatalogLoadsAndPreservesEveryPlaceholder() throws {
        let translations = AppLocalization.translations
        XCTAssertGreaterThan(translations.count, 700)
        func placeholders(_ value: String) -> [String] {
            AppLocalization.placeholderPattern.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .compactMap { Range($0.range, in: value).map { String(value[$0]) } }.sorted()
        }
        for (key, entries) in translations {
            for language in ["ja", "ko", "es"] {
                let value = try XCTUnwrap(entries[language], "Missing \(language): \(key)")
                XCTAssertFalse(value.isEmpty, key)
                XCTAssertEqual(placeholders(value), placeholders(key), "\(language): \(key)")
            }
        }
    }

    @MainActor func testIslandReceivesActualLanguageAndMeasuresTranslatedRequests() {
        let store = IslandLiveStore()
        let display = store.display(english: false, remaining: nil, enabled: true, privacy: false, language: .korean)
        XCTAssertEqual(display.language, .korean)
        XCTAssertEqual(display.connectionTitle, "Codex 대기 중")
        // Model presentation and the SwiftUI environment share this explicit identity.
        XCTAssertEqual(CodexMultitaskCompletionSummary(count: 2, english: false, totalTokens: nil,
            remainingPercent: nil, language: .spanish).compactTitle, "Todo listo · 2 tareas")
    }
}
