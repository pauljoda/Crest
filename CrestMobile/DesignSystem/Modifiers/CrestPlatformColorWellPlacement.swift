import SwiftUI
import UIKit

/// A phone or iPad opens a color well's popover above or below the well,
/// whichever leaves more of the window, and never beside it, where a phone
/// leaves the picker too narrow wherever the well isn't at the screen's edge.
/// The popover's arrow sits on its edge facing the well: its top when it
/// opens below.
struct CrestPlatformColorWellPlacement: ViewModifier {
    @Binding var arrowEdge: Edge?

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .global).midY
        } action: { midY in
            guard let height = windowHeight else { return }
            let edge: Edge = midY < height / 2 ? .top : .bottom
            if arrowEdge != edge { arrowEdge = edge }
        }
    }

    /// The height of the window the well is in, the key window's where there
    /// are several.
    private var windowHeight: CGFloat? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        return window.map(\.bounds.height)
    }
}
