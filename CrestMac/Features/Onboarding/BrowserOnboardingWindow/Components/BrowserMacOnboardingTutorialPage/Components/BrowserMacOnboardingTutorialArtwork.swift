import SwiftUI

struct BrowserMacOnboardingTutorialArtwork: View {
    let tutorial: BrowserMacOnboardingTutorial

    @ViewBuilder
    var body: some View {
        switch tutorial {
        case .spaces:
            BrowserOnboardingHeroPreview()
        case .tabs:
            BrowserMacOnboardingTabsPreview()
        case .sync:
            BrowserMacOnboardingSyncPreview()
        }
    }
}

#Preview("Tutorial Artwork") {
    BrowserMacOnboardingTutorialArtwork(tutorial: .tabs)
        .padding(42)
        .frame(width: 540, height: 540)
        .background(BrowserOnboardingPalette.parchment)
}
