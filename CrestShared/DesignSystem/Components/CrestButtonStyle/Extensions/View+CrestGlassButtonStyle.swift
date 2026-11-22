import SwiftUI

extension View {
    /// Glass buttons where the system draws them, for controls over artwork
    /// or a page. Before macOS 26 they take the bordered style glass replaced,
    /// which also reads over any ground.
    @ViewBuilder
    func crestGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
