import SwiftUI

struct BrowserDeveloperToolbarButtonStyle: ButtonStyle {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? .primary : .secondary)
            .background(
                isActive || configuration.isPressed
                    ? Color.primary.opacity(0.12)
                    : .clear,
                in: .rect(cornerRadius: 7, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.developerPress,
                    reduceMotion: reduceMotion
                ),
                value: configuration.isPressed
            )
    }
}

#Preview("Developer Toolbar Button Style") {
    Button("Inspect", action: {})
        .buttonStyle(BrowserDeveloperToolbarButtonStyle(isActive: true))
        .padding()
}
