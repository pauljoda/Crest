import SwiftUI

extension AnyTransition {
    static var browserCommandPaletteOverlay: AnyTransition {
        .modifier(
            active: BrowserCommandPaletteOverlayTransitionModifier(state: .hidden),
            identity: BrowserCommandPaletteOverlayTransitionModifier(state: .presented)
        )
    }
}
