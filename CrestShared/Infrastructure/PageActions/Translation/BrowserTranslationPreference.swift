import Foundation
@preconcurrency import Translation

/// Translation language availability. The translation choices themselves are
/// core preferences; see `BrowserAppPreferenceStore`.
enum BrowserTranslationPreference {
    // MARK: - Static Variables

    /// Apple's checkers, made once and kept while Crest runs. Each checker
    /// opens a language-status stream to Apple's translation service and
    /// closes it when released. Crest crashed in Translation's stream
    /// bookkeeping while checkers were being made and released in parallel, so
    /// every check shares these. `LanguageAvailability` isn't marked
    /// `Sendable`; parallel checks on one checker rely on Apple guarding its
    /// own state, which is why Translation is imported `@preconcurrency`.
    @MainActor private static let standardAvailability = LanguageAvailability()
    /// Apple's low-latency models, or its default model where they don't exist.
    @MainActor private static let lowLatencyAvailability: LanguageAvailability = {
        guard #available(iOS 26.4, macOS 26.4, *) else { return standardAvailability }
        return LanguageAvailability(preferredStrategy: .lowLatency)
    }()

    // MARK: - Types

    /// Every language Apple translates, and the ones its low-latency models
    /// cover. A pair outside the low-latency models uses Apple's default model.
    struct Languages: Sendable {
        /// Before Apple answers: no languages, and low latency for every pair.
        static let unloaded = Languages(all: [], lowLatencyIDs: [])

        let all: [Locale.Language]
        let lowLatencyIDs: Set<String>

        /// Whether Apple's low-latency models cover both languages. An empty
        /// source is the page's detected language, which they cover when they
        /// cover the target. Apple can answer an empty low-latency list while
        /// those models still translate, so an empty list keeps them for every
        /// pair.
        func usesLowLatency(from source: String, to target: String) -> Bool {
            lowLatencyIDs.isEmpty
                || ((source.isEmpty || lowLatencyIDs.contains(source)) && lowLatencyIDs.contains(target))
        }
    }

    // MARK: - Actions - Languages

    @MainActor static func languages() async -> Languages {
        let general = await standardAvailability.supportedLanguages
        guard #available(iOS 26.4, macOS 26.4, *) else { return Languages(all: general, lowLatencyIDs: []) }
        let lowLatency = await lowLatencyAvailability.supportedLanguages
        let lowLatencyIDs = Set(lowLatency.map(\.minimalIdentifier))
        let generalIDs = Set(general.map(\.minimalIdentifier))
        return Languages(
            all: general + lowLatency.filter { !generalIDs.contains($0.minimalIdentifier) },
            lowLatencyIDs: lowLatencyIDs)
    }

    /// Apple's status for translating `source` to `target`, from the
    /// low-latency models when `lowLatency` and Apple's default model otherwise.
    @MainActor static func status(
        from source: Locale.Language, to target: Locale.Language, lowLatency: Bool
    ) async -> LanguageAvailability.Status {
        await (lowLatency ? lowLatencyAvailability : standardAvailability).status(from: source, to: target)
    }

    nonisolated static func preferredTarget(
        in available: [Locale.Language], preferred: Locale.Language
    ) -> Locale.Language {
        available.first { $0.minimalIdentifier == preferred.minimalIdentifier }
            ?? available.first { $0.languageCode == preferred.languageCode && $0.script == preferred.script }
            ?? preferred
    }
}
