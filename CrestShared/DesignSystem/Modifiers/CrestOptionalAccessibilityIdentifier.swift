import SwiftUI

/// Applies an identifier only when one is supplied, preserving any identifier
/// already published by the wrapped control.
struct CrestOptionalAccessibilityIdentifier: ViewModifier {
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

#Preview("Optional Accessibility Identifier") {
    Text("Space")
        .modifier(
            CrestOptionalAccessibilityIdentifier(
                identifier: "preview-space"
            )
        )
}
