import AppKit

/// Opens the side-panel switcher's menu.
///
/// The view claims only the primary mouse-down, the way `NSPopUpButton` opens
/// on press rather than on release. Every other event falls through to the
/// SwiftUI trigger underneath, so the trigger keeps its hover treatment and
/// stays the control VoiceOver and Full Keyboard Access see.
///
/// `NSMenuItem.target` is a weak reference, so the view — not a short-lived
/// builder — owns the rows for as long as the menu can run.
final class BrowserExtensionSidebarSwitcherMenuAnchorView: NSView {
    var makeModel: (() -> BrowserExtensionSidebarSwitcherMenuModel)?
    var select: ((BrowserExtensionServiceClientID) -> Void)?
    var presentingChanged: ((Bool) -> Void)?
    var hoverChanged: ((Bool) -> Void)?

    private var rows: [BrowserExtensionServiceClientID] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard NSApp.currentEvent?.type == .leftMouseDown else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        presentMenu()
    }

    func presentMenu() {
        guard let model = makeModel?(), model.presentsSwitcher else { return }
        presentingChanged?(true)
        menu(for: model).popUp(positioning: nil, at: menuOrigin, in: self)
        presentingChanged?(false)
        // Tracking areas are quiet during the menu's run loop, so the pointer
        // may have left the trigger without SwiftUI ever hearing about it.
        hoverChanged?(isPointerInside)
    }

    private func menu(for model: BrowserExtensionSidebarSwitcherMenuModel) -> NSMenu {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        rows = model.items.map(\.clientID)
        for (index, item) in model.items.enumerated() {
            let row = NSMenuItem(title: item.title, action: #selector(selectRow(_:)), keyEquivalent: "")
            row.target = self
            row.tag = index
            row.image = item.icon
            row.state = item.isCurrent ? .on : .off
            menu.addItem(row)
        }
        return menu
    }

    /// `popUp` puts the menu's top-left corner at this point, so the menu hangs
    /// from the trigger's bottom edge whichever way this view's y axis runs.
    private var menuOrigin: NSPoint {
        isFlipped
            ? NSPoint(x: bounds.minX, y: bounds.maxY + CrestSpacing.extraExtraSmall)
            : NSPoint(x: bounds.minX, y: bounds.minY - CrestSpacing.extraExtraSmall)
    }

    private var isPointerInside: Bool {
        guard let location = window?.mouseLocationOutsideOfEventStream else { return false }
        return bounds.contains(convert(location, from: nil))
    }

    @objc private func selectRow(_ sender: NSMenuItem) {
        guard rows.indices.contains(sender.tag) else { return }
        select?(rows[sender.tag])
    }
}
