import SwiftUI

/// Pointer drags coexist with row buttons; the browser window draws their previews.
struct BrowserPlatformSidebarReorderLiftGesture: ViewModifier {
    /// A drag must travel this far before it lifts, so a sloppy click still
    /// selects a tab instead of starting a reorder.
    private static let liftDistance: CGFloat = 4

    var isEnabled = true
    let apply: (BrowserSidebarReorderLiftPhase) -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(pointerDrag, including: isEnabled ? .all : .subviews)
    }

    private var pointerDrag: some Gesture {
        DragGesture(
            minimumDistance: Self.liftDistance,
            coordinateSpace: BrowserSidebarReorderSpace.coordinateSpace
        )
        .onChanged { value in
            apply(.moved(startLocation: value.startLocation, location: value.location))
        }
        .onEnded { _ in apply(.released(previewOwner: .application)) }
    }
}
