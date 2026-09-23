import Foundation
import Translation

/// Translation language availability. The translation choices themselves are
/// core preferences; see `BrowserAppPreferenceStore`.
enum BrowserTranslationPreference {
    nonisolated static func languageAvailability() -> LanguageAvailability {
        if #available(iOS 26.4, macOS 26.4, *) {
            return LanguageAvailability(preferredStrategy: .lowLatency)
        }
        return LanguageAvailability()
    }

    nonisolated static func preferredTarget(
        in available: [Locale.Language], preferred: Locale.Language
    ) -> Locale.Language {
        available.first { $0.minimalIdentifier == preferred.minimalIdentifier }
            ?? available.first { $0.languageCode == preferred.languageCode && $0.script == preferred.script }
            ?? preferred
    }
}
