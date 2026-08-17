import SwiftUI

struct BrowserCommandPaletteOverlayTransitionModifier: ViewModifier {
    let state: BrowserCommandPaletteOverlayTransitionState

    func body(content: Content) -> some View {
        content
            .opacity(state.opacity)
            .scaleEffect(state.scale)
    }
}
