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

#Preview("Developer Toolbar Background") {
    BrowserDeveloperToolbarBackground(isOpaque: false)
        .frame(width: 600, height: 42)
}
