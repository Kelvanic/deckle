import XCTest
import SwiftUI
@testable import Deckle

final class LocalizationTests: XCTestCase {
    func testEveryLanguageCatalogAndFallback() throws {
        let englishPath = try XCTUnwrap(AppLanguage.english.bundle.path(forResource: "Localizable", ofType: "strings"))
        let english = try XCTUnwrap(NSDictionary(contentsOfFile: englishPath) as? [String: String])
        for language in AppLanguage.allCases {
            XCTAssertEqual(language.bundle.bundleURL.lastPathComponent.lowercased(),
                           language.rawValue.lowercased() + ".lproj")
            let path = try XCTUnwrap(language.bundle.path(forResource: "Localizable", ofType: "strings"))
            let catalog = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            XCTAssertEqual(Set(english.keys), Set(catalog.keys), language.rawValue)
            for key in english.keys {
                let value = try XCTUnwrap(catalog[key])
                XCTAssertFalse(value.isEmpty, "\(language.rawValue): \(key)")
                XCTAssertEqual(key.components(separatedBy: "%@").count,
                               value.components(separatedBy: "%@").count, "\(language.rawValue): \(key)")
            }
        }
        let settings = ["en": "Settings", "zh-Hans": "设置", "zh-Hant": "設定",
                        "ja": "設定", "ko": "설정", "fr": "Réglages", "de": "Einstellungen",
                        "es": "Ajustes", "pt-BR": "Configurações", "it": "Impostazioni", "ru": "Настройки"]
        for language in AppLanguage.allCases {
            XCTAssertEqual(L("Settings", language: language), settings[language.rawValue])
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
        for language in AppLanguage.allCases {
            state.language = language
            XCTAssertEqual(AppState(defaults: defaults).language, language)
        }
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
            XCTAssertEqual(L("Settings"), L("Settings", language: language))
            XCTAssertEqual(AppLanguage.current, language)
            let starter = DeskSetup.starters[0]
            XCTAssertEqual(starter.displayName, L("Read"))
            let decoded = try JSONDecoder().decode(DeskSetup.self, from: JSONEncoder().encode(starter))
            XCTAssertEqual(decoded.displayName, starter.displayName)
            let custom = DeskSetup(name: "Read", textureID: "clear-veil", intensity: 0.22,
                                   grainScale: 1, grainStrength: 1)
            XCTAssertEqual(custom.displayName, "Read")
            let paper = TexturePreset.preset(id: "clear-veil")
            XCTAssertTrue(PaperSearch.matches(paper, query: paper.displayName, isCustom: false))
            XCTAssertEqual(TexturePreset(custom: CustomPaper(name: "Clear Veil")).displayName, "Clear Veil")
            for tab in QuickControlsView.ControlTab.allCases {
                let view = QuickControlsView(isExpanded: .constant(true), selectedTab: .constant(tab), versionOverride: packageVersion)
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

extension LocalizationTests {
    @MainActor
    func testExistingSettingsViewRefreshesAfterLanguageChanges() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: AppLanguage.preferenceKey)
        defer {
            if let original { defaults.set(original, forKey: AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        let state = AppState(defaults: defaults)
        let host = NSHostingView(rootView: QuickControlsView(
            isExpanded: .constant(true), selectedTab: .constant(.settings), versionOverride: packageVersion)
            .environmentObject(state).padding(14).frame(width: 370))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: 640),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        var previousImage: Data?
        for language in AppLanguage.allCases {
            state.language = language
            try await Task.sleep(nanoseconds: 30_000_000)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            if let previousImage { XCTAssertNotEqual(image, previousImage, language.rawValue) }
            previousImage = image
            if let directory = ProcessInfo.processInfo.environment["DECKLE_I18N_RENDER_DIR"] {
                try image.write(to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("live-settings-\(language.rawValue).png"))
            }
            XCTAssertEqual(AppLanguage.current, language)
            let message = localizedUpdateMessage("Update failed — detail")
            XCTAssertEqual(message, String(format: L("Update failed — %@"), "detail"))
            XCTAssertEqual(localizedUpdateMessage(UpdateManager.InstallBlocker.notAnApp.userMessage),
                           L(UpdateManager.InstallBlocker.notAnApp.userMessage))
        }
    }

}

extension LocalizationTests {
    @MainActor
    func testAllLocalizedSurfacesFitTheirWindow() throws {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: AppLanguage.preferenceKey)
        defer {
            if let original { defaults.set(original, forKey: AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        let suite = "DeckleSurfaceRender.\(UUID().uuidString)"
        let isolated = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { isolated.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: isolated)
        for language in AppLanguage.allCases {
            defaults.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            state.language = language
            let surfaces: [(String, AnyView, CGFloat)] = [
                ("menu", AnyView(MenuView()), 370),
                ("desk", AnyView(VStack { HeroCardView(); DeskSetupsView() }.padding(14)), 370),
                ("library", AnyView(PresetCollectionView(searchText: .constant(""),
                    isShowingAllGrid: .constant(true)).padding(14)), 370),
                ("pets", AnyView(PetsView().padding(14)), 370),
                ("editor", AnyView(PaperMillView(draft: CustomPaper(name: "Review paper"),
                    isNew: true, dismiss: {}, state: state)), 430),
            ]
            for (name, view, width) in surfaces {
                let root = view.environmentObject(state)
                    .environment(\.locale, Locale(identifier: language.rawValue))
                    .frame(width: width)
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: root)
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width, width, accuracy: 1, "\(language): \(name)")
                XCTAssertGreaterThan(host.fittingSize.height, 0)
                if let directory = ProcessInfo.processInfo.environment["DECKLE_I18N_RENDER_DIR"] {
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: URL(fileURLWithPath: directory)
                            .appendingPathComponent("\(language.rawValue)-\(name).png"))
                }
            }
        }
    }
}

extension LocalizationTests {
    private var packageVersion: String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let info = NSDictionary(contentsOf: root.appendingPathComponent("Support/Info.plist"))
        return info?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
