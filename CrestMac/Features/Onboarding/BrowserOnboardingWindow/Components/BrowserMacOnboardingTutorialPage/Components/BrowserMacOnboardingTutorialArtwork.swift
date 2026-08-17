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
