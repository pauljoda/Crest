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
        /// Whether the panel is editing a color well in this popover: the
        /// popover was on screen as the panel opened, which a click on its own
        /// well does and which closes any other popover, or one of its wells
        /// became the panel's since.
        private var opensPanel = false
        /// Whether the panel was open when the popover last looked.
        private var panelWasOpen = false
        /// Follows the clicks and keys the popover's window handles.
        private var eventMonitor: Any?

        // MARK: - Actions - Observation

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            guard window != nil else { return }
            let observations: [(Selector, Notification.Name)] = [
                (#selector(popoverDidShow), NSPopover.didShowNotification),
                (#selector(windowDidChangeOcclusion), NSWindow.didChangeOcclusionStateNotification),
                (#selector(windowWillClose), NSWindow.willCloseNotification),
                (#selector(panelColorDidChange), NSColorPanel.colorDidChangeNotification),
            ]
            for (selector, name) in observations {
                NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
            }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
                self?.windowWillHandle(event)
                return event
            }
        }

        /// A well clicked while the panel already shows its color becomes the
        /// panel's without the panel posting anything, so the popover looks
        /// again once its window has handled the click or key.
        private func windowWillHandle(_ event: NSEvent) {
            guard event.window === window else { return }
            DispatchQueue.main.async { [weak self] in self?.followColorsPanel() }
        }

        @objc private func popoverDidShow(_ notification: Notification) {
            guard let shown = notification.object as? NSPopover, let window,
                shown.contentViewController?.view.window === window
            else { return }
            popover = shown
            behavior = shown.behavior
            // A popover that opens over a panel already open isn't the one
            // whose well opened it.
            panelWasOpen = Self.panelIsOpen
            opensPanel = false
            followColorsPanel()
        }

        @objc private func windowDidChangeOcclusion(_ notification: Notification) {
            guard notification.object is NSColorPanel else { return }
            // The well that opens the panel becomes active as the panel shows.
            DispatchQueue.main.async { [weak self] in self?.followColorsPanel() }
        }

        /// A well that becomes the panel's sets the panel to its color.
        @objc private func panelColorDidChange(_ notification: Notification) {
            followColorsPanel()
        }

        @objc private func windowWillClose(_ notification: Notification) {
            guard notification.object is NSColorPanel else { return }
            // The panel is still visible while it closes.
            DispatchQueue.main.async { [weak self] in self?.followColorsPanel() }
        }

        // MARK: - Actions - Lookup

        private static var panelIsOpen: Bool {
            NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible
        }

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
            let panelIsOpen = Self.panelIsOpen
            if panelIsOpen, !panelWasOpen { opensPanel = true }
            if panelIsOpen, popover.contentViewController.map({ Self.holdsActiveColorWell($0.view) }) == true {
                opensPanel = true
            }
            if !panelIsOpen { opensPanel = false }
            panelWasOpen = panelIsOpen
            popover.behavior = panelIsOpen && opensPanel ? .semitransient : behavior
        }
    }
}
