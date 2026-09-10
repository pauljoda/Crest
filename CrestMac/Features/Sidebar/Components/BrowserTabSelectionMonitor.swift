import AppKit
import SwiftUI

/// One event owner per active sidebar. Modifier clicks never reach page
/// activation, while ordinary clicks and drags keep their existing controls.
struct BrowserTabSelectionMonitor: NSViewRepresentable {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let assignment: BrowserSpaceRuntimeAssignment
    let activate: (TabID) -> Void
    var ownsFocus = false

    func makeNSView(context: Context) -> SelectionView { SelectionView() }

    func updateNSView(_ view: SelectionView, context: Context) {
        view.browser = browser
        view.spaceAccess = spaceAccess
        view.assignment = assignment
        view.activate = activate
        if ownsFocus, browser.session.selectedSpaceID == assignment.spaceID,
            view.window?.attachedSheet == nil,
            view.window?.firstResponder !== view
        {
            view.window?.makeFirstResponder(view)
        }
    }

    static func dismantleNSView(_ view: SelectionView, coordinator: ()) { view.stop() }

    final class SelectionView: NSView {
        weak var browser: BrowserStore?
        weak var spaceAccess: BrowserSpaceAccessController?
        var assignment: BrowserSpaceRuntimeAssignment?
        var activate: ((TabID) -> Void)?
        private var monitor: Any?
        private var consumedDown = false
        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resignFirstResponder() -> Bool {
            browser?.tabMultiSelection.ownsKeyboardFocus = false
            return super.resignFirstResponder()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [
                .leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown,
            ]) {
                [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.window === window, let browser, let spaceAccess, let assignment,
                browser.session.selectedSpaceID == assignment.spaceID
            else { return event }
            guard
                BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                    matching: assignment, in: browser, accessController: spaceAccess) != nil
            else {
                browser.tabMultiSelection.clear()
                return event
            }
            let selection = browser.tabMultiSelection
            if event.type == .keyDown {
                if event.keyCode == 53, selection.isEngaged, browser.sidebarReorderState.hasLiftInFlight {
                    browser.sidebarReorderState.cancel()
                    selection.clear()
                    return nil
                }
                guard window?.firstResponder === self else { return event }
                return handleKey(event, browser: browser)
            }
            if event.type == .leftMouseUp {
                if consumedDown {
                    consumedDown = false
                    return nil
                }
                return event
            }
            guard let window,
                let id = BrowserNativeTabSelectionTarget.TargetView.item(
                    at: event.locationInWindow, in: window, browser: browser, assignment: assignment)
            else {
                selection.clear()
                return event
            }
            let units = BrowserSidebarSelection.itemUnits(in: browser)
            selection.reconcile(units: units)
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                if !selection.contains(id) { selection.clear() }
                return event
            }
            let command = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            if command || shift {
                selection.click(id, units: units, command: command, shift: shift)
                window.makeFirstResponder(self)
                consumedDown = true
                return nil
            }
            // Preserve a selected set on mouse-down so dragging it carries the
            // set. The activation button collapses it only after a plain click.
            if !selection.contains(id) { selection.click(id, units: units) }
            return event
        }

        private func handleKey(_ event: NSEvent, browser: BrowserStore) -> NSEvent? {
            let selection = browser.tabMultiSelection
            let units = BrowserSidebarSelection.itemUnits(in: browser)
            selection.reconcile(units: units)
            let command = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            if event.keyCode == 53 {
                browser.sidebarReorderState.cancel()
                selection.clear()
                return nil
            }
            if command, event.charactersIgnoringModifiers?.lowercased() == "a" {
                if shift { selection.clear() } else { selection.selectAll(units: units) }
                return nil
            }
            if command, !shift, !event.modifierFlags.contains(.option),
                !event.modifierFlags.contains(.control), let id = selection.focusedItem,
                let request = BrowserSidebarSelection.request(for: id, browser: browser), let spaceAccess
            {
                let actions = BrowserTabBatchActions(browser: browser, spaceAccess: spaceAccess)
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c":
                    actions.copyLinks(request)
                    return nil
                case "d":
                    actions.perform(request, action: .duplicate)
                    return nil
                case "w":
                    actions.perform(request, action: .close)
                    return nil
                default: break
                }
                if event.keyCode == 51 {
                    actions.perform(request, action: .delete)
                    return nil
                }
            }
            if [123, 124, 125, 126, 115, 119].contains(event.keyCode), !units.isEmpty {
                let current =
                    units.firstIndex { $0.contains(selection.focusedItem ?? selection.anchorItem ?? units[0][0]) } ?? 0
                let backwards = event.keyCode == 123 || event.keyCode == 126 || event.keyCode == 115
                let edge = command || event.keyCode == 115 || event.keyCode == 119
                let index =
                    edge
                    ? (backwards ? 0 : units.count - 1) : min(max(current + (backwards ? -1 : 1), 0), units.count - 1)
                selection.click(units[index][0], units: units, command: command && !edge, shift: shift)
                if !shift { selection.selectForKeyboard(units[index][0], units: units) }
                return nil
            }
            if event.keyCode == 36, let id = selection.focusedItem {
                if let tabID = id.tabID { activate?(tabID) }
                if let folderID = id.folderID,
                    let folder = browser.selectedSpace?.folders.first(where: { $0.id == folderID })
                {
                    browser.setFolderCollapsed(
                        folderID, in: browser.session.selectedSpaceID, isCollapsed: !folder.isCollapsed)
                }
                return nil
            }
            return event
        }

        override func selectAll(_ sender: Any?) {
            guard let browser else { return }
            browser.tabMultiSelection.selectAll(units: BrowserSidebarSelection.itemUnits(in: browser))
        }
    }
}
