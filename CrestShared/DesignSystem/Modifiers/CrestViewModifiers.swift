import SwiftUI

private struct BrowserReadableForegroundModifier: ViewModifier {
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

private struct CrestOptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier, identifier.contains(where: { !$0.isWhitespace }) {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

private struct CrestOptionalAccessibilityValue: ViewModifier {
    let value: Text?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}

extension View {
    func browserReadableForeground(over background: Color) -> some View {
        modifier(BrowserReadableForegroundModifier(background: background))
    }

    /// Applies an identifier only when one is supplied, preserving any identifier
    /// already published by the wrapped control.
    func crestAccessibilityIdentifier(_ identifier: String?) -> some View {
        modifier(CrestOptionalAccessibilityIdentifier(identifier: identifier))
    }

    /// Publishes a spoken value only when the component has meaningful detail to
    /// add beyond its accessibility label.
    func crestAccessibilityValue(_ value: Text?) -> some View {
        modifier(CrestOptionalAccessibilityValue(value: value))
    }
}
