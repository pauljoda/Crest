import SwiftUI

struct BrowserSettingsLabeledActionButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, BrowserSettingsControlPolicy.horizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: BrowserSettingsControlPolicy.labeledActionHeight
            )
            .fixedSize(horizontal: false, vertical: true)
            .background(
                tint.opacity(
                    configuration.isPressed
                        ? BrowserSettingsControlPolicy.labeledPressedFillOpacity
                        : BrowserSettingsControlPolicy.restingFillOpacity
                ),
                in: RoundedRectangle(
                    cornerRadius: BrowserSettingsControlPolicy.cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: BrowserSettingsControlPolicy.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    tint.opacity(BrowserSettingsControlPolicy.labeledBorderOpacity),
                    lineWidth: BrowserSettingsControlPolicy.borderWidth
                )
            }
            .contentShape(.rect)
            .scaleEffect(
                configuration.isPressed
                    ? BrowserSettingsControlPolicy.labeledPressedScale
                    : 1
            )
            .opacity(
                isEnabled ? 1 : BrowserSettingsControlPolicy.labeledDisabledOpacity
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

#Preview("Settings Action Button") {
    Button("Import Browser Data", systemImage: "square.and.arrow.down") {}
        .buttonStyle(BrowserSettingsLabeledActionButtonStyle())
        .padding()
        .frame(width: 320)
}
