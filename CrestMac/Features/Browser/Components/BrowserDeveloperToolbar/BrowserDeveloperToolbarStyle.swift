import SwiftUI

/// The device's surface material, striped so the bar reads as a developer tool.
struct BrowserDeveloperToolbarBackground: View {
    let isOpaque: Bool

    var body: some View {
        Canvas { context, size in
            drawStripes(in: &context, size: size)
        }
        .background { CrestSurfaceLayer(shape: Rectangle()) }
        .accessibilityHidden(true)
    }

    private func drawStripes(in context: inout GraphicsContext, size: CGSize) {
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
                .foregroundStyle(isActive ? .primary : .secondary)
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

/// The bar's buttons: the design system's chrome surface, which shows a
/// tool that is on as selected, with the bar's own press motion.
private struct BrowserDeveloperToolbarButtonStyle: ButtonStyle {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        CrestChromeButtonStyle(
            controlSize: CGSize(
                width: BrowserDeveloperToolbarMetrics.buttonSize,
                height: BrowserDeveloperToolbarMetrics.buttonSize
            ),
            isSelected: isActive
        )
        .makeBody(configuration: configuration)
        .scaleEffect(configuration.isPressed ? 0.94 : 1)
        .animation(
            CrestMotion.developerPress.unlessReducingMotion(reduceMotion),
            value: configuration.isPressed
        )
    }
}

enum BrowserDeveloperToolbarMetrics {
    static let itemSpacing: Double = 5
    static let buttonSize: Double = 28
    static let dividerHeight: Double = 22
    static let dividerPadding: Double = 2
}
