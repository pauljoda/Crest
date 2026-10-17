import SwiftUI

/// The stage's backdrop: a sidebar field in `branding`, darkened so the page
/// reads over it. A change of look cross-fades.
struct BrowserOnboardingBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let branding: SpaceBranding

    /// Counts the looks the backdrop has worn, so each is a field of its own
    /// that fades in over the last.
    @State private var generation = 0

    var body: some View {
        ZStack {
            BrowserSpaceBannerBackground(branding: branding)
                .id(generation)
                .transition(.opacity)
            Color.black.opacity(BrowserOnboardingStageMetrics.backdropShade)
        }
        .onChange(of: branding) { _, _ in
            withAnimation(CrestMotion.onboardingBackdrop.unlessReducingMotion(reduceMotion)) { generation += 1 }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
