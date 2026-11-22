import AppKit
import SwiftUI

/// Has the popover its content is shown in take a new size in one step once
/// it is on screen, rather than animating its frame while SwiftUI lays the
/// content out at the new size, which slides everything in it as it grows.
struct CrestPlatformInstantPopoverResizing: ViewModifier {
    func body(content: Content) -> some View {
        content.background { PopoverFinder() }
    }
}

/// Finds the popover its view is shown in as it shows, and stops it
/// animating changes of size.
private struct PopoverFinder: NSViewRepresentable {
    func makeNSView(context: Context) -> FindingView {
        FindingView()
    }

    func updateNSView(_ view: FindingView, context: Context) {}

    final class FindingView: NSView {
        // MARK: - Actions - Observation

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard window != nil else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(popoverDidShow), name: NSPopover.didShowNotification, object: nil)
        }

        @objc private func popoverDidShow(_ notification: Notification) {
            guard let shown = notification.object as? NSPopover, let window,
                shown.contentViewController?.view.window === window
            else { return }
            shown.animates = false
        }
    }
}
