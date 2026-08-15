import SwiftUI

/// Names which card of a split the browser chrome is speaking for.
///
/// It rides on the outer rounded rectangle of the page surface — the same
/// radius `BrowserRootContentSurface` clips to — as an overlay rather than as a
/// change to that shared surface, so the single-page path keeps rendering
/// exactly the frame it always has. The stroke is the Space's own accent,
/// because the focused card is a statement about this window's Space rather
/// than about the system tint.
///
/// A window presenting one card has nothing to disambiguate, so callers omit
/// this entirely rather than drawing an always-on ring.
struct BrowserSplitCardFocusIndicator: View {
    let isFocused: Bool
    let accent: Color

    private static let strokeWidth: CGFloat = 2
    private static let focusedOpacity = 0.9

    var body: some View {
        RoundedRectangle(
            cornerRadius: BrowserChromeLayout.pageCornerRadius,
            style: .continuous
        )
        .strokeBorder(
            accent.opacity(isFocused ? Self.focusedOpacity : 0),
            lineWidth: Self.strokeWidth
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Split Card Focus Indicator", traits: .fixedLayout(width: 520, height: 300)) {
    HStack(spacing: BrowserSplitLayoutMetrics.interCardGap) {
        ForEach([true, false], id: \.self) { isFocused in
            Color.gray.opacity(0.2)
                .clipShape(
                    .rect(
                        cornerRadius: BrowserChromeLayout.pageCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    BrowserSplitCardFocusIndicator(
                        isFocused: isFocused,
                        accent: .indigo
                    )
                }
        }
    }
    .padding(BrowserChromeLayout.pageFrameInset)
}
