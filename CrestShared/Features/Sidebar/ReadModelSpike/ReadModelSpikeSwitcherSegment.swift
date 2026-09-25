#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: one Space's switcher
    /// segment.
    struct ReadModelSpikeSwitcherSegment: View {
        // MARK: - Types

        /// Everything the segment's body reads.
        struct Shown: Equatable {
            let name: String
            let symbol: String
            let accent: SpaceAccent

            @MainActor
            init(settings: SpaceSettingsModel) {
                name = settings.name
                symbol = settings.symbol
                accent = settings.accent
            }
        }

        // MARK: - Variables

        let settings: SpaceSettingsModel
        let isShown: Bool

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.segment)
            #endif
            let shown = Shown(settings: settings)
            Image(systemName: shown.symbol)
                .foregroundStyle(isShown ? shown.accent.color : .secondary)
                .frame(width: 24, height: 24)
                .accessibilityLabel(shown.name)
        }
    }
#endif
