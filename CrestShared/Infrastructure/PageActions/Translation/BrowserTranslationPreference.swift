import Foundation
import Translation

@MainActor
enum BrowserTranslationPreference {
    static let automaticKey = "crest.translation.automaticallyTranslate"

    static let defaults: UserDefaults = {
        let environment = BrowserLaunchEnvironment.current
        guard BrowserLaunchIsolationPolicy.requiresIsolation(environment) else { return .standard }
        let id = environment.persistentIsolationID ?? "ephemeral-\(UUID().uuidString)"
        return UserDefaults(suiteName: BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(isolationID: id))!
    }()

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
