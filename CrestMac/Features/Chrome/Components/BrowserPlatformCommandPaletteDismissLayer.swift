import AppKit
import SwiftUI

/// The space around a palette grown out of an address field, which a click
/// closes the palette from. It is a view of its own, as the page below is, so
/// a click over the page reaches it rather than the page.
struct BrowserPlatformCommandPaletteDismissLayer: NSViewRepresentable {
    let dismiss: () -> Void

    func makeNSView(context: Context) -> ClickView { ClickView() }

    func updateNSView(_ view: ClickView, context: Context) {
        view.dismiss = dismiss
    }

    final class ClickView: NSView {
        var dismiss: () -> Void = {}

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { dismiss() }
        override func rightMouseDown(with event: NSEvent) { dismiss() }
        override func isAccessibilityElement() -> Bool { false }
    }
}
