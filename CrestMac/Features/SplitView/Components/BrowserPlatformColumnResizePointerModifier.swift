import AppKit
import SwiftUI

/// macOS owns a real column-resize pointer, so the divider can say what it does
/// before anyone grabs it.
///
/// `pointerStyle(_:)` and `PointerStyle.columnResize` are macOS 15 and later,
/// well under Crest's macOS 26.1 deployment target, so the affordance needs no
/// availability fork of its own — only the platform fork this file is.
///
/// The pointer style applies when the pointer enters the handle. A handle
/// overhangs the pages beside it, and a Chromium page sets the arrow when the
/// pointer leaves it, after the handle's style already applied; with no new
/// entry the arrow stayed across the rest of the handle. The handle therefore
/// holds the cursor on each move inside it, and once more after that move's
/// event, which runs after the page's exit. Holding it explicitly means the
/// handle also hands it back: once the pointer leaves, a cursor nothing else
/// has replaced returns to the arrow.
struct BrowserPlatformColumnResizePointerModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .pointerStyle(.columnResize)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                    holdResizeCursor()
                case .ended:
                    isHovering = false
                    releaseResizeCursor()
                }
            }
    }

    private func holdResizeCursor() {
        NSCursor.columnResize.set()
        Task { @MainActor in
            if isHovering { NSCursor.columnResize.set() }
        }
    }

    private func releaseResizeCursor() {
        Task { @MainActor in
            guard !isHovering, Self.showsResizeCursor else { return }
            NSCursor.arrow.set()
        }
    }

    /// Whether the cursor showing is still the resize cursor, rather than
    /// one the view under the pointer set since.
    private static var showsResizeCursor: Bool {
        let current = NSCursor.current
        let resize = NSCursor.columnResize
        return current.hotSpot == resize.hotSpot && current.image.size == resize.image.size
    }
}
