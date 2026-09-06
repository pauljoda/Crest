import AppKit
import WebKit

/// Remembers the mouse press that dismissed a transient popup. The matching
/// button release consumes it; a later press is a new request, even if fast.
struct BrowserExtensionPopupToggleState<Key: Hashable> {
    private var mouseDown: TimeInterval?
    private var dismissal: (key: Key, mouseDown: TimeInterval)?

    mutating func beganMouseDown(at timestamp: TimeInterval) {
        mouseDown = timestamp
        if dismissal?.mouseDown != timestamp { dismissal = nil }
    }

    mutating func dismissed(_ key: Key, at timestamp: TimeInterval) {
        mouseDown = timestamp
        dismissal = (key, timestamp)
    }

    mutating func consume(_ key: Key) -> Bool {
        defer { dismissal = nil }
        return dismissal?.key == key && dismissal?.mouseDown == mouseDown
    }

    var currentMouseDown: TimeInterval? { mouseDown }
}

@MainActor
final class BrowserExtensionPopupToggle {
    private final class PresentedPopup {
        weak var popover: NSPopover?
        weak var action: WKWebExtension.Action?
        init(_ popover: NSPopover, action: WKWebExtension.Action) {
            self.popover = popover
            self.action = action
        }
    }

    private var state = BrowserExtensionPopupToggleState<ObjectIdentifier>()
    private var monitor: Any?
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var closing: [ObjectIdentifier: UUID] = [:]
    private var afterClose: [ObjectIdentifier: [() -> Void]] = [:]
    private var presentedPopups: [ObjectIdentifier: PresentedPopup] = [:]

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        for observer in observers.values { NotificationCenter.default.removeObserver(observer) }
        for observer in closeObservers.values { NotificationCenter.default.removeObserver(observer) }
    }

    func observe(
        _ popover: NSPopover, action: WKWebExtension.Action, key: ObjectIdentifier,
        anchor: BrowserExtensionPopupAnchor?,
        runtimeDidReload: @escaping @MainActor () -> Void = {}
    ) {
        presentedPopups[key] = PresentedPopup(popover, action: action)
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.state.beganMouseDown(at: event.timestamp)
                return event
            }
        }
        if let previous = observers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(previous)
        }
        observers[key] = NotificationCenter.default.addObserver(
            forName: NSPopover.willCloseNotification, object: popover, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.closing[key] == nil { self.closing[key] = UUID() }
                self.presentedPopups[key] = nil
                guard let event = NSApp.currentEvent,
                    event.type == .leftMouseDown || event.type == .leftMouseUp,
                    anchor?.contains(event: event) == true,
                    let timestamp = event.type == .leftMouseDown ? event.timestamp : self.state.currentMouseDown
                else { return }
                self.state.dismissed(key, at: timestamp)
            }
        }
        if let previous = closeObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(previous)
        }
        closeObservers[key] = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification, object: popover, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishedClosing(key) }
        }
        // WebKit exposes no runtime reload notification and leaves a
        // host-presented popover alive after replacing its action. Check only
        // while this popup is visible; ordinary browsing has no polling work.
        Task { @MainActor [weak self, weak popover, weak action] in
            while true {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let popover, popover.isShown,
                    self.presentedPopups[key]?.popover === popover
                else { return }
                guard let action, let context = action.webExtensionContext, context.isLoaded,
                    context.action(for: action.associatedTab) === action
                else {
                    if let action { action.closePopup() }
                    if popover.isShown { popover.close() }
                    runtimeDidReload()
                    return
                }
            }
        }
    }

    func forget(_ key: ObjectIdentifier) {
        if let observer = observers.removeValue(forKey: key) { NotificationCenter.default.removeObserver(observer) }
        if let observer = closeObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(observer)
        }
        presentedPopups[key] = nil
        closing[key] = nil
        afterClose[key] = nil
    }

    func afterClosing(_ key: ObjectIdentifier, perform: @escaping () -> Void) {
        guard let closeID = closing[key] else {
            perform()
            return
        }
        afterClose[key, default: []].append(perform)
        // Keep a missed native close notification from stranding a new click.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.finishedClosing(key, expectedID: closeID)
        }
    }

    private func finishedClosing(_ key: ObjectIdentifier, expectedID: UUID? = nil) {
        if let expectedID, closing[key] != expectedID { return }
        closing[key] = nil
        let callbacks = afterClose.removeValue(forKey: key) ?? []
        for callback in callbacks { callback() }
    }

    func closeIfShown(for key: ObjectIdentifier) -> Bool {
        guard let presented = presentedPopups[key], presented.popover?.isShown == true,
            let action = presented.action
        else { return false }
        // The close animation can outlive WebKit clearing its action popup.
        // A new click must not dismiss that old surface a second time.
        presentedPopups[key] = nil
        if closing[key] == nil { closing[key] = UUID() }
        action.closePopup()
        return true
    }

    func consumeDismissal(for key: ObjectIdentifier) -> Bool {
        // Keyboard and accessibility invocations are independent of the last
        // pointer dismissal and must still be able to open the popup.
        guard NSApp.currentEvent?.type == .leftMouseUp || NSApp.currentEvent?.type == .leftMouseDown else {
            _ = state.consume(key)
            return false
        }
        return state.consume(key)
    }
}
