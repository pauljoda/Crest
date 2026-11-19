import SwiftUI

/// Crest's paper, which setup lies on: the canvas, under a fine grain.
struct BrowserSetupPaper: View {
    // MARK: - Actions - Drawing

    var body: some View {
        ZStack {
            CrestBrandTheme.canvas
            CrestGrain()
                .blendMode(.softLight)
                .opacity(BrowserSetupPaperMetrics.grain)
        }
    }
}

enum BrowserSetupPaperMetrics {
    static let grain = 0.35
}
