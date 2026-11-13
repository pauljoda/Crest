import AppKit
import SwiftUI

/// A browser window's tab preview on the Mac: the shared layer, drawing the
/// pictures the window's pages keep, which it starts them keeping, and told
/// where the sidebar's edge and the pointer are. A key, a click or a scroll
/// in the window takes the card down, or the card on its way, as does the
/// window losing focus, the command palette opening, the window showing
/// another Space or its Space locking. While the pointer is in the card, a
/// floating sidebar stays out.
struct BrowserMacTabPreviewLayer: View {
    // MARK: - Variables

    let model: BrowserRootModel

    private var preview: BrowserTabPreviewState { model.sidebarInteraction.tabPreview }

    /// How far the sidebar's page edge is from its side of the window: its
    /// width when docked, and its inset too when it floats over the page.
    private var sidebarEdge: CGFloat {
        let presentation = model.sidebarPresentation
        return presentation.reservesSidebarWidth
            ? model.sidebarWidth : BrowserSidebarPresentation.floatingCardInset + model.sidebarWidth
    }

    // MARK: - Actions - Presentation

    var body: some View {
        let preview = self.preview
        let pictures = model.pages.tabPictures
        BrowserTabPreviewLayer(preview: preview, sidebarEdge: sidebarEdge) { pictures.previewPicture(of: $0) }
            .background {
                BrowserMacTabPreviewDismissal(preview: preview, isActive: preview.shown != nil)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                BrowserMacTabPreviewPointer(preview: preview)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .onChange(of: preview.isPointerInCard || preview.inner.isPointerInCard) { _, isInside in
                model.chrome.utilityPresentation.setTabPreviewHeld(isInside)
            }
            .onChange(of: isDragging) { _, isDragging in
                holdForInteraction(isDragging)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                holdForInteraction(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                holdForInteraction(false)
            }
            .onChange(of: model.isWindowFocused) { _, isFocused in
                if !isFocused { preview.dismiss() }
            }
            .onChange(of: model.chrome.isCommandPalettePresented) { _, isPresented in
                if isPresented { preview.dismiss() }
            }
            .onChange(of: model.browser.shownSpace?.id) { preview.dismiss() }
            .onChange(of: model.browser.shownSpace.map(model.spaceAccess.isLocked) ?? false) { _, isLocked in
                if isLocked { preview.dismiss() }
            }
            .onAppear {
                let spaceAccess = model.spaceAccess
                pictures.follow { spaceAccess.isLocked($0) }
            }
            .onDisappear { model.chrome.utilityPresentation.setTabPreviewHeld(false) }
    }
}

extension BrowserMacTabPreviewLayer {
    // MARK: - Actions - Holding

    /// Whether a sidebar drag is under way, by the pointer's lift or a
    /// system drag.
    private var isDragging: Bool {
        let interaction = model.sidebarInteraction
        return interaction.sidebarReorderState.isDragging || interaction.tabDragState.item != nil
    }

    /// Keeps the card up through a drag or a menu that begins in it, such as
    /// a tab dragged out of a folder's card or a row's menu, and lets it go
    /// once that ends.
    private func holdForInteraction(_ isUnderWay: Bool) {
        guard !isUnderWay || preview.isPointerInCard || preview.inner.isPointerInCard else { return }
        preview.interactionChanged(isUnderWay)
    }
}

/// Tells the window's tab preview where the pointer is in the window, in the
/// points from its top left that the sidebar measures its tabs in.
private struct BrowserMacTabPreviewPointer: NSViewRepresentable {
    // MARK: - Variables

    let preview: BrowserTabPreviewState

    // MARK: - Actions - Representation

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let location: @MainActor () -> CGPoint? = { [weak view] in
            guard let window = view?.window, let content = window.contentView else { return nil }
            let location = window.mouseLocationOutsideOfEventStream
            return CGPoint(x: location.x, y: content.bounds.height - location.y)
        }
        preview.pointerLocation = location
        preview.inner.pointerLocation = location
    }
}

/// Takes the card down, or the card on its way, when the person presses a
/// key, clicks or scrolls in the window, tells the preview when they type,
/// and gives the keyboard back to whatever held it once a card goes.
///
/// Escape goes no further than a card that shows. A click or a scroll inside
/// the card is the card's own, and a folder's card stays up for keys, which
/// go wherever they were going, into its search once that has the keyboard.
/// The arrow keys leave the card up, since they move the sidebar's keyboard
/// focus and the card follows it. Anything else takes the card down and goes
/// on to where it was going.
private struct BrowserMacTabPreviewDismissal: NSViewRepresentable {
    // MARK: - Types

    final class Coordinator {
        weak var view: NSView?
        var preview: BrowserTabPreviewState?
        var monitor: Any?
        /// What held the keyboard as the card showed.
        weak var previousResponder: NSResponder?

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    // MARK: - Static Variables

    private static let escapeKeyCode: UInt16 = 53
    private static let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]
    private static let events: NSEvent.EventTypeMask = [
        .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
    ]

    // MARK: - Variables

    let preview: BrowserTabPreviewState
    /// Whether a card shows, read by the layer so a card showing or going
    /// updates this view.
    let isActive: Bool

    // MARK: - Actions - Representation

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.preview = preview
        if coordinator.monitor == nil {
            coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: Self.events) { [weak coordinator] event in
                guard let coordinator, let window = coordinator.view?.window, event.window === window else {
                    return event
                }
                // A key code is a key event's alone, and asking a click for
                // one raises an exception; a location is a pointer event's.
                let type = event.type
                let isKey = type == .keyDown
                let keyCode = isKey ? event.keyCode : 0
                let location = isKey ? .zero : event.locationInWindow
                let modifiers = event.modifierFlags
                let consumed = MainActor.assumeIsolated {
                    Self.handle(
                        type: type, keyCode: keyCode, modifiers: modifiers, location: location, in: window,
                        coordinator: coordinator)
                }
                return consumed ? nil : event
            }
        }
        if isActive, coordinator.previousResponder == nil {
            coordinator.previousResponder = view.window?.firstResponder
        } else if !isActive, let responder = coordinator.previousResponder {
            coordinator.previousResponder = nil
            Self.restoreKeyboard(in: view.window, to: responder)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }

    // MARK: - Actions - Events

    /// Takes the card down for an event unless the card keeps it, and
    /// answers whether the card consumed the event, as it does Escape.
    @MainActor
    private static func handle(
        type: NSEvent.EventType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, location: CGPoint,
        in window: NSWindow, coordinator: Coordinator
    ) -> Bool {
        guard let preview = coordinator.preview else { return false }
        if type == .keyDown { preview.keyPressed() }
        guard preview.isEngaged else { return false }
        if type == .keyDown {
            if keyCode == escapeKeyCode, modifiers.intersection([.command, .control, .option]).isEmpty {
                let showsCard = preview.shown != nil
                preview.dismiss()
                return showsCard
            }
            if arrowKeyCodes.contains(keyCode) || preview.shown?.subject.capturesKeys == true { return false }
            preview.dismiss()
            return false
        }
        if let content = window.contentView {
            let point = CGPoint(x: location.x, y: content.bounds.height - location.y)
            if preview.shownCardFrames.contains(where: { $0.contains(point) }) { return false }
        }
        preview.dismiss()
        return false
    }

    /// Puts the keyboard back on `responder` when a card that took it left the
    /// window holding nothing, as a folder's search does when its card goes.
    @MainActor
    private static func restoreKeyboard(in window: NSWindow?, to responder: NSResponder?) {
        guard let window, let responder, window.firstResponder === window || window.firstResponder == nil else {
            return
        }
        if let view = responder as? NSView, view.window !== window { return }
        window.makeFirstResponder(responder)
    }
}
