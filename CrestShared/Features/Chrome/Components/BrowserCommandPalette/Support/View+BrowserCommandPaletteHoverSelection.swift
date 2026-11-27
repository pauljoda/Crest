import SwiftUI

extension View {
    /// Tells `model` where the pointer moves over the palette, so a row it
    /// then moves onto is selected at once.
    @MainActor
    func browserCommandPalettePointerTracking(model: BrowserCommandPaletteModel) -> some View {
        onContinuousHover(coordinateSpace: .global) { phase in
            guard case .active(let point) = phase else { return }
            model.pointerMoved(to: point)
        }
    }

    @MainActor
    func browserCommandPaletteHoverSelection(
        model: BrowserCommandPaletteModel,
        index: Int
    ) -> some View {
        onContinuousHover(coordinateSpace: .global) { phase in
            guard case .active(let point) = phase else { return }
            model.pointerMoved(to: point, over: index)
        }
    }
}
