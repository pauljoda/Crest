import SwiftUI

extension View {
    @MainActor
    func browserCommandPaletteHoverSelection(
        model: BrowserCommandPaletteModel,
        item: BrowserCommandPaletteItem
    ) -> some View {
        modifier(BrowserPlatformCommandPaletteHoverSelection(model: model, item: item))
    }
}
