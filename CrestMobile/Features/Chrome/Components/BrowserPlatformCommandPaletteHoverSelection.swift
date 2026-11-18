import SwiftUI

struct BrowserPlatformCommandPaletteHoverSelection: ViewModifier {
    let model: BrowserCommandPaletteModel
    let item: BrowserCommandPaletteItem

    func body(content: Content) -> some View {
        content.onHover { isHovering in
            guard isHovering else { return }
            model.selectResult(item)
        }
    }
}
