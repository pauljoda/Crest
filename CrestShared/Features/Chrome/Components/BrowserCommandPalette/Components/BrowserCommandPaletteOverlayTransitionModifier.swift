import SwiftUI

struct BrowserCommandPaletteOverlayTransitionModifier: ViewModifier {
    let state: BrowserCommandPaletteOverlayTransitionState

    func body(content: Content) -> some View {
        content
            .opacity(state.opacity)
            .scaleEffect(state.scale)
    }
}

#Preview("Command Palette Overlay Transition") {
    Label("Command Palette", systemImage: "command")
        .font(.title2.weight(.semibold))
        .padding(CrestSpacing.extraLarge)
        .background(
            .regularMaterial,
            in: .rect(cornerRadius: BrowserCommandPaletteMetrics.cardCornerRadius)
        )
        .modifier(
            BrowserCommandPaletteOverlayTransitionModifier(
                state: BrowserCommandPaletteOverlayTransitionState(
                    opacity: 0.72,
                    scale: 0.96
                )
            )
        )
        .padding(CrestSpacing.large)
}
