import SwiftUI

/// Crest's paper, which onboarding lies on: ink, Crest's navy, under a fine
/// grain, the same in the light and the dark. What lies on it reads as it
/// does in the dark, as `browserSetupPaperContent()` sets.
struct BrowserSetupPaper: View {
    // MARK: - Static Variables

    /// The scheme what lies on the paper reads in: light on navy, in the
    /// light as in the dark.
    static let colorScheme = ColorScheme.dark
    /// A card, a row or a waiting chip raised on the paper: slate, the
    /// brand's lighter navy.
    static let raisedFill = CrestBrandPalette.slateComponents.color
    /// The hairline round something raised on the paper.
    static let raisedEdge = Color.white.opacity(BrowserSetupPaperMetrics.raisedEdge)

    // MARK: - Actions - Drawing

    var body: some View {
        ZStack {
            CrestBrandPalette.ink
            CrestGrain()
                .blendMode(.softLight)
                .opacity(BrowserSetupPaperMetrics.grain)
        }
    }
}

enum BrowserSetupPaperMetrics {
    static let grain = 0.35
    static let raisedEdge = 0.12
}

extension EnvironmentValues {
    /// Whether the view lies on setup's paper, rather than on a Space's look
    /// or on Crest's own surfaces.
    @Entry var liesOnBrowserSetupPaper = false
}
