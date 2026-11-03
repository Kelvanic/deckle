import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case brazilianPortuguese = "pt-BR"
    case italian = "it"
    case russian = "ru"

    static let preferenceKey = "appLanguage"
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .english
    }
    var id: String { rawValue }
    var label: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .brazilianPortuguese: return "Português (Brasil)"
        case .italian: return "Italiano"
        case .russian: return "Русский"
        }
    }

    private static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "Deckle_Deckle", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()

    var bundle: Bundle {
        // SwiftPM normalizes locale directory names to lowercase, while
        // Xcode's universal build can preserve the source spelling.
        for name in [rawValue, rawValue.lowercased()] {
            if let url = Self.resources.resourceURL?.appendingPathComponent(name + ".lproj"),
               let bundle = Bundle(url: url) { return bundle }
        }
        return Self.resources
    }
}

/// English keys remain readable fallbacks when a translation is unavailable.
func L(_ key: String, language: AppLanguage = .current) -> String {
    language.bundle.localizedString(forKey: key, value: key, table: nil)
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale(identifier: AppLanguage.current.rawValue), arguments: arguments)
}

/// Status stores English messages so an open failure banner can change language.
func localizedUpdateMessage(_ message: String) -> String {
    let prefix = "Update failed — "
    if message.hasPrefix(prefix) {
        return LF("Update failed — %@", String(message.dropFirst(prefix.count)))
    }
    return L(message)
}
