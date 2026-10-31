import SwiftUI

/// The stage's backdrop: a sidebar field in `branding`, darkened so the page
/// reads over it. A change of look cross-fades from the field shown before,
/// as `fade` paces it.
struct BrowserOnboardingBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let branding: SpaceBranding
    let fade: Animation

    /// The look the field shows, which follows `branding` one fade behind,
    /// and how many looks it has worn, so each is a field of its own that
    /// fades in over the last.
    @State private var shown: SpaceBranding
    @State private var generation = 0

    init(branding: SpaceBranding, fade: Animation) {
        self.branding = branding
        self.fade = fade
        _shown = State(initialValue: branding)
    }

    var body: some View {
        ZStack {
            BrowserSpaceBannerBackground(branding: shown)
                .id(generation)
                .transition(.opacity)
            Color.black.opacity(BrowserOnboardingStageMetrics.backdropShade)
        }
        .onChange(of: branding) { _, next in
            withAnimation(fade.unlessReducingMotion(reduceMotion)) {
                shown = next
                generation += 1
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
