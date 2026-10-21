import AppKit
import SwiftUI

/// The floating window the recent tabs show in: a child of the Crest window
/// that never becomes key or main, so the page keeps the keyboard, and that
/// stays out of the Window menu, Mission Control and window cycling.
final class RecentTabSwitcherPanel: NSPanel {
    // MARK: - Variables

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Initializers

    init<Content: View>(rootView: Content, pointerMoved: @escaping @MainActor (CGPoint) -> Void) {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        setAccessibilityLabel(String(localized: "Recent tabs"))
        contentView = RecentTabSwitcherHostingView(rootView: rootView, pointerMoved: pointerMoved)
    }

    // MARK: - Actions - Placement

    /// The frame of a panel `size` large centred on `owner`, slid back inside
    /// `visibleFrame` when it would reach past the display.
    static func frame(size: CGSize, centeredOn owner: CGRect, within visibleFrame: CGRect) -> CGRect {
        var origin = CGPoint(x: owner.midX - size.width / 2, y: owner.midY - size.height / 2)
        origin.x = min(max(origin.x, visibleFrame.minX), max(visibleFrame.maxX - size.width, visibleFrame.minX))
        origin.y = min(max(origin.y, visibleFrame.minY), max(visibleFrame.maxY - size.height, visibleFrame.minY))
        return CGRect(origin: origin, size: size)
    }
}

/// Takes a click and follows the pointer even though its window is never key,
/// where SwiftUI's own hover does not arrive.
private final class RecentTabSwitcherHostingView<Content: View>: NSHostingView<Content> {
    private let pointerMoved: @MainActor (CGPoint) -> Void

    init(rootView: Content, pointerMoved: @escaping @MainActor (CGPoint) -> Void) {
        self.pointerMoved = pointerMoved
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: Content) { fatalError("init(rootView:) has not been implemented") }

    @available(*, unavailable)
    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointerMoved(CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y))
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
}
