import XCTest
import SwiftUI
@testable import Deckle

final class LocalizationTests: XCTestCase {
    func testChineseCatalogAndFallback() throws {
        let englishPath = try XCTUnwrap(AppLanguage.english.bundle.path(forResource: "Localizable", ofType: "strings"))
        let chinesePath = try XCTUnwrap(AppLanguage.simplifiedChinese.bundle.path(forResource: "Localizable", ofType: "strings"))
        let english = try XCTUnwrap(NSDictionary(contentsOfFile: englishPath) as? [String: String])
        let chinese = try XCTUnwrap(NSDictionary(contentsOfFile: chinesePath) as? [String: String])
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        for key in english.keys {
            XCTAssertFalse(try XCTUnwrap(chinese[key]).isEmpty, key)
            XCTAssertEqual(key.components(separatedBy: "%@").count,
                           chinese[key]?.components(separatedBy: "%@").count, key)
        }
        let clearVeil = TexturePreset.preset(id: "clear-veil")
        XCTAssertTrue(PaperSearch.matches(clearVeil, query: "清透", isCustom: false))
        XCTAssertEqual(TexturePreset(custom: CustomPaper(name: "Clear Veil")).displayName, "Clear Veil")
        XCTAssertEqual(L("Settings", language: .simplifiedChinese), "设置")
        XCTAssertEqual(L("Settings", language: .english), "Settings")
        XCTAssertEqual(L("User-created title", language: .simplifiedChinese), "User-created title")
    }

    @MainActor
    func testLanguagePreferenceSurvivesRelaunchAndUnknownValuesRecover() throws {
        let suite = "DeckleLocalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.language, .english)
        state.language = .simplifiedChinese
        XCTAssertEqual(AppState(defaults: defaults).language, .simplifiedChinese)
        defaults.set("unknown-language", forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppState(defaults: defaults).language, .english)
    }

    @MainActor
    func testLanguageSwitchAndCompactSettingsRender() throws {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: AppLanguage.preferenceKey)
        defer {
            if let original { defaults.set(original, forKey: AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        let suite = "DeckleLanguageRender.\(UUID().uuidString)"
        let isolated = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { isolated.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: isolated)
        for language in AppLanguage.allCases {
            defaults.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            state.language = language
            XCTAssertEqual(L("Settings"), language == .english ? "Settings" : "设置")
            for tab in QuickControlsView.ControlTab.allCases {
                let view = QuickControlsView(isExpanded: .constant(true), selectedTab: .constant(tab))
                    .environmentObject(state)
                    .environment(\.locale, Locale(identifier: language.rawValue))
                    .padding(14).frame(width: 370)
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: view)
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width, 370, accuracy: 1)
                if let directory = ProcessInfo.processInfo.environment["DECKLE_I18N_RENDER_DIR"] {
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: URL(fileURLWithPath: directory)
                            .appendingPathComponent("\(language.rawValue)-\(tab.id).png"))
                }
            }
        }
    }
}
