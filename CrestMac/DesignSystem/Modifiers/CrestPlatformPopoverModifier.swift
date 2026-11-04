import AppKit
import SwiftUI

/// Keeps a Crest popover open while the system Colors panel is on screen. A
/// popover closes when the person clicks outside it, and the panel a color
/// well opens is outside it, so typing a hex value there put the popover and
/// its color well away. While the panel is open the popover closes only for a
/// click in its own window, and once the panel closes it goes back to closing
/// for any click outside it.
struct CrestPlatformPopoverModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background { ColorsPanelHold() }
    }
}

/// Finds the popover its view is shown in and follows the Colors panel.
private struct ColorsPanelHold: NSViewRepresentable {
    func makeNSView(context: Context) -> HoldingView {
        HoldingView()
    }

    func updateNSView(_ view: HoldingView, context: Context) {}

    final class HoldingView: NSView {
        // MARK: - Variables

        private weak var popover: NSPopover?
        /// How the popover closes when the panel isn't open.
        private var behavior = NSPopover.Behavior.transient

        // MARK: - Actions - Observation

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard window != nil else { return }
            let observations: [(Selector, Notification.Name)] = [
                (#selector(popoverDidShow), NSPopover.didShowNotification),
                (#selector(windowDidChangeOcclusion), NSWindow.didChangeOcclusionStateNotification),
                (#selector(windowWillClose), NSWindow.willCloseNotification),
            ]
            for (selector, name) in observations {
                NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
            }
        }

        @objc private func popoverDidShow(_ notification: Notification) {
            guard let shown = notification.object as? NSPopover, let window,
                shown.contentViewController?.view.window === window
            else { return }
            popover = shown
            behavior = shown.behavior
            followColorsPanel()
        }

        @objc private func windowDidChangeOcclusion(_ notification: Notification) {
            guard notification.object is NSColorPanel else { return }
            followColorsPanel()
        }

        @objc private func windowWillClose(_ notification: Notification) {
            guard notification.object is NSColorPanel else { return }
            // The panel is still visible while it closes.
            DispatchQueue.main.async { [weak self] in self?.followColorsPanel() }
        }

        // MARK: - Mutators

        private func followColorsPanel() {
            guard let popover else { return }
            let panelIsOpen = NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible
            popover.behavior = panelIsOpen ? .semitransient : behavior
        }
    }
}
