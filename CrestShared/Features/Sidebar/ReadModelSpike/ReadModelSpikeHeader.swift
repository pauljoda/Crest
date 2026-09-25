#if DEBUG || CREST_PERFORMANCE_HARNESS
    import SwiftUI

    /// S6.4 spike, DEBUG and performance builds only: the Space's header.
    struct ReadModelSpikeHeader: View {
        // MARK: - Types

        /// Everything the header's body reads.
        struct Shown: Equatable {
            let name: String
            let symbol: String
            let accent: SpaceAccent
            let branding: SpaceBranding?

            @MainActor
            init(settings: SpaceSettingsModel) {
                name = settings.name
                symbol = settings.symbol
                accent = settings.accent
                branding = settings.branding
            }
        }

        // MARK: - Variables

        let settings: SpaceSettingsModel

        var body: some View {
            #if CREST_PERFORMANCE_HARNESS
                let _ = ReadModelSpikeBodyCount.count(.header)
            #endif
            let shown = Shown(settings: settings)
            HStack(spacing: 8) {
                Image(systemName: shown.symbol).foregroundStyle(shown.accent.tint.color)
                Text(shown.name).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                if shown.branding != nil { Image(systemName: "paintpalette").font(.caption) }
            }
        }
    }
#endif
