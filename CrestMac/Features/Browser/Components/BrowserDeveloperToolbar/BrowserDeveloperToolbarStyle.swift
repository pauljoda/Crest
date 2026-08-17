import AppKit
import SwiftUI

struct BrowserDeveloperToolbarBackground: View {
    let isOpaque: Bool

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(
            Path(bounds),
            with: .color(
                isOpaque
                    ? Color(nsColor: .windowBackgroundColor)
                    : Color(nsColor: .underPageBackgroundColor).opacity(0.92)
            )
        )
        for x in stride(from: -size.height, through: size.width, by: 22) {
            var stripe = Path()
            stripe.move(to: CGPoint(x: x, y: 0))
            stripe.addLine(to: CGPoint(x: x + size.height, y: size.height))
            context.stroke(
                stripe,
                with: .color(.white.opacity(isOpaque ? 0.025 : 0.045)),
                lineWidth: 8
            )
        }
    }
}

struct BrowserDeveloperToolbarButton: View {
    let label: LocalizedStringKey
    let systemImage: String
    var isActive = false
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(
                    width: BrowserDeveloperToolbarMetrics.buttonSize,
                    height: BrowserDeveloperToolbarMetrics.buttonSize
                )
                .contentShape(.rect)
        }
        .buttonStyle(BrowserDeveloperToolbarButtonStyle(isActive: isActive))
        .accessibilityLabel(Text(label))
        .help(Text(label))
    }
}

struct BrowserDeveloperToolbarDivider: View {
    var body: some View {
        Divider()
            .frame(height: BrowserDeveloperToolbarMetrics.dividerHeight)
            .padding(.horizontal, BrowserDeveloperToolbarMetrics.dividerPadding)
            .accessibilityHidden(true)
    }
}

private struct BrowserDeveloperToolbarButtonStyle: ButtonStyle {
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

enum BrowserDeveloperToolbarMetrics {
    static let itemSpacing: Double = 5
    static let horizontalPadding: Double = 10
    static let height: Double = 42
    static let separatorHeight: Double = 0.5
    static let buttonSize: Double = 28
    static let dividerHeight: Double = 22
    static let dividerPadding: Double = 2
}
