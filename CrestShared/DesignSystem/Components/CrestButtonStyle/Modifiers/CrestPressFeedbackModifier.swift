import SwiftUI

struct CrestPressFeedbackModifier: ViewModifier {
    let isPressed: Bool
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                BrowserVisualAccessibilityPolicy.spatialScale(
                    isPressed ? CrestButtonMetrics.pressedScale : 1,
                    reduceMotion: reduceMotion
                )
            )
            .opacity(isEnabled ? 1 : CrestButtonMetrics.disabledOpacity)
            .animation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.press,
                    reduceMotion: reduceMotion
                ),
                value: isPressed
            )
    }
}
