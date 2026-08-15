import SwiftUI

/// Publishes a spoken value only when the component has meaningful detail to
/// add beyond its accessibility label.
struct CrestOptionalAccessibilityValue: ViewModifier {
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

#Preview("Optional Accessibility Value") {
    Text("Space")
        .modifier(CrestOptionalAccessibilityValue(value: Text("Selected")))
}
