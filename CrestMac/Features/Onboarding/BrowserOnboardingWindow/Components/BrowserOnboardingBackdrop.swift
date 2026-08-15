import SwiftUI

struct BrowserOnboardingBackdrop: View {
    var body: some View {
        BrowserOnboardingPalette.parchment
            .ignoresSafeArea()
    }
}

#Preview("Onboarding Backdrop") {
    BrowserOnboardingBackdrop()
        .frame(width: 520, height: 320)
}
