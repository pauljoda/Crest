import SwiftUI

/// The sidebar's hover area, filled with Crest blue while someone
/// adjusts its width and fading out about three seconds after the last change.
///
/// It is drawn behind the strip itself, so it only shows where the strip is and
/// never takes input: the strip and the page underneath keep answering the
/// pointer.
struct BrowserSidebarRevealZonePreview: View {
    // MARK: - Static Variables

    /// How long the area stays at full strength after the last change before
    /// it fades, and how long the fade takes.
    private static let fadeDelay: Duration = .seconds(0.5)
    private static let fadeDuration: TimeInterval = 2.5
    /// How long Reduce Motion holds the area before it goes at once: about as
    /// long as the hold and fade together.
    private static let reducedMotionHold: Duration = .seconds(3)

    // MARK: - Variables

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 0.0
    @State private var fade: Task<Void, Never>?

    private let preview = SidebarRevealWidthPreview.shared

    var body: some View {
        CrestBrandTheme.accent
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: preview.adjustmentCount) { restartFade() }
            .onDisappear { fade?.cancel() }
    }

    /// Full strength straight away, then gone three seconds after the last
    /// adjustment. Reduce Motion holds it and removes it without the fade.
    private func restartFade() {
        fade?.cancel()
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { opacity = 1 }
        fade = Task {
            if reduceMotion {
                try? await Task.sleep(for: Self.reducedMotionHold)
                guard !Task.isCancelled else { return }
                opacity = 0
            } else {
                try? await Task.sleep(for: Self.fadeDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: Self.fadeDuration)) { opacity = 0 }
            }
        }
    }
}
