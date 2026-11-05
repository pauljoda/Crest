import AppKit
import SwiftUI

/// Keeps a Crest popover open while the system Colors panel is editing a color
/// well inside it. A popover closes when the person clicks outside it, and the
/// panel is outside it, so typing a hex value there put the popover and its
/// color well away. While the panel edits its well the popover closes only for
/// a click in its own window; once the panel closes, or for any popover whose
/// well it isn't editing, a click anywhere outside closes it as before.
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
            // The well that opens the panel becomes active as the panel shows.
            DispatchQueue.main.async { [weak self] in self?.followColorsPanel() }
        }

        @objc private func windowWillClose(_ notification: Notification) {
            guard notification.object is NSColorPanel else { return }
            // The panel is still visible while it closes.
            DispatchQueue.main.async { [weak self] in self?.followColorsPanel() }
        }

        // MARK: - Actions - Lookup

        /// Whether `view` or a view inside it is a color well the Colors panel
        /// is editing now.
        private static func holdsActiveColorWell(_ view: NSView) -> Bool {
            (view as? NSColorWell)?.isActive == true || view.subviews.contains(where: holdsActiveColorWell)
        }

        // MARK: - Mutators

        /// Holds the popover only while the panel is open for a color well
        /// inside it, so any other popover, such as a permission request,
        /// still closes for a click anywhere outside it.
        private func followColorsPanel() {
            guard let popover else { return }
            let panelIsOpen = NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible
            let opensPanel = popover.contentViewController.map { Self.holdsActiveColorWell($0.view) } ?? false
            popover.behavior = panelIsOpen && opensPanel ? .semitransient : behavior
        }
    }
}
