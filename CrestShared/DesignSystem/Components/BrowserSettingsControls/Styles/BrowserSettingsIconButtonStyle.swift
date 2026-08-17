import SwiftUI

struct BrowserSettingsIconButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(
                width: BrowserSettingsControlPolicy.minimumTouchTarget,
                height: BrowserSettingsControlPolicy.minimumTouchTarget
            )
            .background(
                tint.opacity(
                    configuration.isPressed
                        ? BrowserSettingsControlPolicy.iconPressedFillOpacity
                        : BrowserSettingsControlPolicy.restingFillOpacity
                ),
                in: RoundedRectangle(
                    cornerRadius: BrowserSettingsControlPolicy.cornerRadius,
                    style: .continuous
                )
            )
            .contentShape(.rect)
            .scaleEffect(
                configuration.isPressed
                    ? BrowserSettingsControlPolicy.iconPressedScale
                    : 1
            )
            .opacity(
                isEnabled ? 1 : BrowserSettingsControlPolicy.iconDisabledOpacity
            )
            .animation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.compactPress,
                    reduceMotion: reduceMotion
                ),
                value: configuration.isPressed
            )
    }
}
