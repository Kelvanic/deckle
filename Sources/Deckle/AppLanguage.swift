import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let preferenceKey = "appLanguage"
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .english
    }
    var id: String { rawValue }
    var label: String { self == .english ? "English" : "简体中文" }

    private static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "Deckle_Deckle", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()

    var bundle: Bundle {
        guard let path = Self.resources.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return Self.resources }
        return bundle
    }
}

/// English keys remain readable fallbacks when a translation is unavailable.
func L(_ key: String, language: AppLanguage = .current) -> String {
    language.bundle.localizedString(forKey: key, value: key, table: nil)
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale(identifier: AppLanguage.current.rawValue), arguments: arguments)
}
