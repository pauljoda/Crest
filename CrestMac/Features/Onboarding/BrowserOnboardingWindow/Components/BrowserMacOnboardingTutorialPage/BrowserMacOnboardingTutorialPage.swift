import SwiftUI

struct BrowserMacOnboardingTutorialPage: View {
    let tutorial: BrowserMacOnboardingTutorial
    let back: () -> Void
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                BrowserMacOnboardingTutorialCopy(tutorial: tutorial)
                    .frame(
                        maxWidth: 440,
                        maxHeight: .infinity,
                        alignment: .leading
                    )
                    .padding(48)
                    .background(BrowserOnboardingPalette.paper)

                BrowserMacOnboardingTutorialArtwork(tutorial: tutorial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(42)
                    .background(BrowserOnboardingPalette.parchment)
            }

            HStack {
                Button("Back", action: back)
                    .buttonStyle(BrowserOnboardingSecondaryButtonStyle())
                    .accessibilityIdentifier("onboarding-feature-back")
                Spacer()
                Button(action: next) {
                    HStack {
                        Text(tutorial.primaryTitle)
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(BrowserOnboardingPrimaryButtonStyle())
                .controlSize(.large)
                .accessibilityIdentifier("onboarding-feature-next")
            }
            .padding(18)
            .background(BrowserOnboardingPalette.paper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(BrowserOnboardingPalette.line)
                    .frame(height: 1)
            }
        }
    }
}
