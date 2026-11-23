import Foundation

/// Search metadata only; looking for a paper must not render its texture.
enum PaperSearch {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func matches(_ preset: TexturePreset, query: String, isCustom: Bool) -> Bool {
        let tags = [preset.isDark ? "dark black" : "light white",
                    preset.weave != nil ? "weave woven cotton" : "smooth",
                    isCustom ? "custom my paper" : "built in",
                    preset.isQuietReading ? "quiet reading low pattern" : ""]
        let metadata = [
            preset.name, preset.subtitle, preset.id,
            L(preset.name), L(preset.subtitle),
            L(preset.name, language: .simplifiedChinese),
            L(preset.subtitle, language: .simplifiedChinese),
        ]
        let searchable = normalized((metadata + tags).joined(separator: " "))
        return normalized(query).split(separator: " ").allSatisfy { searchable.contains($0) }
    }
}
