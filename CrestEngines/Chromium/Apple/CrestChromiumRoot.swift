#if CREST_CHROMIUM_HOST
import AppKit
import SwiftUI

/// Chromium owns the process and AppController. Crest owns the same window
/// composition, stores, and SwiftUI views used by its WebKit application.
@objc(CrestRoot) @MainActor
final class CrestChromiumRoot: NSObject {
    private static var instance: CrestChromiumRoot?
    static var engineHost: (any CrestChromiumEngineHost)? { instance?.host }
    private let host: any CrestChromiumEngineHost
    private let application: BrowserMacApplication
    private var windows: [BrowserWindowID: NSWindow] = [:]
    private var eventMonitor: Any?
    private var quitting = false
    private var hasStopped = false

    @objc(startWithHost:)
    static func start(host: any CrestChromiumEngineHost) {
        guard instance == nil else { return }
        let root = CrestChromiumRoot(host: host)
        instance = root
        root.openWindow(.initial)
        root.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleShortcutEvent(event) ? nil : event
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(host: any CrestChromiumEngineHost) {
        self.host = host
        application = BrowserMacApplication()
        super.init()
        // Popup adoption will be connected to the shared tab runtime next.
        // Reject unowned WebContents instead of leaving invisible native tabs.
        host.setBrowserObserver { values in
            MainActor.assumeIsolated {
                if let token = values["adoptionId"] as? String { host.rejectAdoption(token) }
            }
        }
    }

    static func openNativeWindow(_ request: BrowserMacWindowRequest) { instance?.openWindow(request) }

    private func openWindow(_ request: BrowserMacWindowRequest) {
        if let existing = windows[request.id] { existing.makeKeyAndOrderFront(nil); return }
        guard application.windowCoordinator.model(for: request) != nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(request.id.rawValue.uuidString)
        window.title = "Crest"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 720, height: 500)
        window.isReleasedWhenClosed = false
        windows[request.id] = window
        window.contentViewController = NSHostingController(rootView: application.browserWindowContent(request))
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)),
            name: NSWindow.willCloseNotification, object: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private var activeModel: BrowserMacWindowModel? {
        guard let window = NSApp.keyWindow,
            let id = windows.first(where: { $0.value === window })?.key else { return nil }
        return application.windowCoordinator.existingModel(for: id)
    }

    private var actions: BrowserCommandActions? {
        guard let model = activeModel else { return nil }
        return BrowserCommandActions(browser: model.browser, pages: model.pages, chrome: model.chrome,
            openWindow: EnvironmentValues().openWindow, spaceAccess: application.spaceAccess, targetWindowID: model.id)
    }

    @objc private func windowClosed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let id = windows.first(where: { $0.value === window })?.key else { return }
        windows.removeValue(forKey: id)
        application.windowCoordinator.closeWindow(id)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    }

    @objc(windowForIdentifier:)
    static func window(for identifier: String?) -> NSWindow? {
        guard let instance else { return nil }
        if let identifier { return instance.windows.values.first { $0.identifier?.rawValue == identifier } }
        return instance.windows.values.first
    }

    @objc static func deferQuit() -> Bool {
        guard let instance, !instance.hasStopped else { return false }
        guard !instance.quitting else { return true }
        instance.quitting = true
        instance.host.prepareToQuit { allowed in
            MainActor.assumeIsolated {
                guard allowed else { instance.quitting = false; return }
                Task { @MainActor in
                    for id in Array(instance.windows.keys) {
                        guard let model = instance.application.windowCoordinator.existingModel(for: id) else { continue }
                        await model.browser.flushPendingSyncPersistence()
                        await model.windowState.flushPendingPersistence()
                        await model.pages.flushPendingTabStateWrites()
                    }
                    instance.host.disposePages()
                    instance.hasStopped = true
                    instance.host.completeQuit()
                }
            }
        }
        return true
    }

    @objc static func handleShortcutEvent(_ event: NSEvent) -> Bool {
        guard let instance, event.type == .keyDown,
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
            let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if key == "q" { return deferQuit() }
        guard !instance.quitting else { return true }
        if key == "n" { instance.openWindow(.normal(sourceWindowID: instance.activeModel?.id)); return true }
        guard let model = instance.activeModel, let actions = instance.actions else { return false }
        switch key {
        case "l": actions.openLocation()
        case "t": actions.openNewTab()
        case "w": actions.closeTabOrWindow()
        case "r": model.pages.reloadOrStop(in: model.browser.session)
        case "[": model.pages.goBack()
        case "]": model.pages.goForward()
        case ",": model.browser.openSettings(); model.pages.select(session: model.browser.session)
        default: return false
        }
        return true
    }

    @objc static func showNativeNotice(_ message: String, icon: String) {
        guard let window = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: window)
    }
    @objc static func focusOmnibox() { instance?.actions?.openLocation() }
    @objc static func toggleBookmark(forURL url: String, title: String) { instance?.actions?.toggleSelectedTabPinned() }
    @objc static func shareURL(_ url: String, title: String) {
        guard let item = URL(string: url), let view = NSApp.keyWindow?.contentView else { return }
        NSSharingServicePicker(items: [item]).show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }
    @objc static func showQRCode(forURL url: String, title: String) { showNativeNotice("QR sharing is not yet connected in this host.", icon: "qrcode") }
    @objc static func translateURL(_ url: String) { showNativeNotice("Translation is not yet connected in this host.", icon: "globe") }
    @objc static func translateText(_ text: String) { showNativeNotice("Translation is not yet connected in this host.", icon: "globe") }
    @objc static func showTabSearch() { instance?.activeModel?.chrome.presentCommandPalette() }
}
#endif
