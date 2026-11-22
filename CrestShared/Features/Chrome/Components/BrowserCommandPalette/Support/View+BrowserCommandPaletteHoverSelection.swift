import SwiftUI

extension View {
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
