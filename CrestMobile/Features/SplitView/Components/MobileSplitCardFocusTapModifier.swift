import SwiftUI

/// Makes a tap on a card that has no web content ask for focus.
///
/// The live-page case gets its focus tap from `MobileBrowserWebView`, which
/// installs a `UITapGestureRecognizer` on the web host with
/// `cancelsTouchesInView = false` — the only arrangement that both hears the tap
/// and still lets the page have it. A placeholder or failure card has no host to
/// install anything on, so an ordinary SwiftUI gesture is exactly right there.
///
/// A `nil` action leaves the view untouched rather than attaching a gesture that
/// does nothing, so the carousel — where the visible card is already focused —
/// adds no recognizer at all.
struct MobileSplitCardFocusTapModifier: ViewModifier {
    let requestFocus: (() -> Void)?

    func body(content: Content) -> some View {
        if let requestFocus {
            content.simultaneousGesture(TapGesture().onEnded(requestFocus))
        } else {
            content
        }
    }
}

#Preview("Split Card Focus Tap", traits: .fixedLayout(width: 260, height: 160)) {
    @Previewable @State var focusRequestCount = 0

    RoundedRectangle(cornerRadius: CrestRadius.card)
        .fill(.quaternary)
        .overlay {
            Text("Focus requests: \(focusRequestCount)")
                .font(.caption)
        }
        .modifier(
            MobileSplitCardFocusTapModifier(
                requestFocus: { focusRequestCount += 1 }
            )
        )
        .padding()
}
