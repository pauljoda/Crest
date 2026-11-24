import SwiftUI

/// A popup row's resting, hovered, pressed and selected treatment, where its
/// shell draws one.
///
/// A plain button style everywhere else: a band's rows are aimed at with a
/// finger, which never rests, and a highlight that only ever appears under the
/// thumb already covering it is noise.
struct BrowserCredentialPopupRowStyle: ButtonStyle {
    let isSelected: Bool
    let highlightCornerRadius: CGFloat?

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if let highlightCornerRadius {
            configuration.label
                .crestHoverSurface(
                    isSelected: isSelected,
                    cornerRadius: highlightCornerRadius,
                    isPressed: configuration.isPressed
                )
        } else {
            configuration.label
        }
    }
}
