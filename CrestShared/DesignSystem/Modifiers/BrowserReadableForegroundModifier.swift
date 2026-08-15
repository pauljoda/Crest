import SwiftUI

struct BrowserReadableForegroundModifier: ViewModifier {
    let background: Color

    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        content.foregroundStyle(
            BrowserVisualAccessibilityPolicy.readableForeground(
                over: background,
                environment: environment
            )
        )
    }
}
