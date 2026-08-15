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

#Preview("Command Palette Shell Materials") {
    HStack(spacing: CrestSpacing.large) {
        Text("Glass")
            .frame(width: 180, height: 100)
            .modifier(
                BrowserCommandPaletteShellMaterial(
                    reduceTransparency: false
                )
            )

        Text("Reduced Transparency")
            .frame(width: 180, height: 100)
            .modifier(
                BrowserCommandPaletteShellMaterial(
                    reduceTransparency: true
                )
            )
    }
    .padding(CrestSpacing.large)
    .background(CrestBrandTheme.canvas)
}
