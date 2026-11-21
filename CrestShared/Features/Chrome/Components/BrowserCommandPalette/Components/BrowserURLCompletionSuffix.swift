import SwiftUI

/// Drawn at the native caret without becoming part of the editable value.
struct BrowserURLCompletionSuffix: View {
    /// How strongly the suggested rest of the address reads, and how bright
    /// the shimmer that crosses it gets at its peak.
    private static let restingOpacity = 0.65
    private static let shimmerPeakOpacity = 0.95

    let text: String
    let font: Font
    var isVisible = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if isVisible {
                if reduceMotion || contrast == .increased {
                    label.foregroundStyle(Color.secondary.opacity(contrast == .increased ? 1 : Self.restingOpacity))
                } else {
                    label.phaseAnimator([false, true]) { content, sweepsRight in
                        let position = sweepsRight ? 1.35 : -0.35
                        content.foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.secondary.opacity(Self.restingOpacity),
                                    Color.secondary.opacity(Self.shimmerPeakOpacity),
                                    Color.secondary.opacity(Self.restingOpacity),
                                ],
                                startPoint: UnitPoint(x: position - 0.25, y: 0.5),
                                endPoint: UnitPoint(x: position + 0.25, y: 0.5)
                            )
                        )
                    } animation: { sweepsRight in
                        sweepsRight
                            ? .linear(duration: 1.6).delay(2.4)
                            : .linear(duration: 0)
                    }
                }
            }
        }
        // Each proposal owns a fresh shimmer. Never animate the previous text or
        // its layout into the next keystroke's preview.
        .id(text)
        .transition(.identity)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var label: some View {
        Text(verbatim: text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserURLCompletionSuffix(text: "browser.com", font: .title2).padding()
    }
#endif
