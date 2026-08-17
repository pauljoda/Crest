import SwiftUI

struct BrowserCommandPaletteShellMaterial: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                .background,
                in: .rect(
                    cornerRadius: BrowserCommandPaletteMetrics.cardCornerRadius,
                    style: .continuous
                )
            )
        } else {
            content.glassEffect(
                .regular,
                in: .rect(cornerRadius: BrowserCommandPaletteMetrics.cardCornerRadius)
            )
        }
    }
}
