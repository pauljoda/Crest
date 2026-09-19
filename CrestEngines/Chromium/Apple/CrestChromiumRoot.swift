#if CREST_CHROMIUM_HOST
import AppKit
import SwiftUI

/// Loaded by Chromium after its AppController and browser threads are ready.
/// This framework deliberately has no @main or NSApplication delegate.
@objc(CrestRoot) @MainActor
final class CrestChromiumRoot: NSObject {
    private static var instance: CrestChromiumRoot?
    private let host: any CrestChromiumEngineHost
    private let model: ControlPlaneModel
    private var windows: [String: NSWindow] = [:]
    private var eventMonitor: Any?
    private var quitting = false

    @objc(startWithHost:)
    static func start(host: any CrestChromiumEngineHost) {
        guard instance == nil else { return }
        let root = CrestChromiumRoot(host: host)
        instance = root
        root.openWindow()
        root.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleShortcutEvent(event) ? nil : event
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    private init(host: any CrestChromiumEngineHost) {
        self.host = host
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        model = ControlPlaneModel(
            engine: ChromiumAdapter(host: host),
            storageDirectory: support.appendingPathComponent("CrestChromiumControlPlane", isDirectory: true))
        super.init()
        model.onStopped = { [weak self] in self?.host.completeQuit() }
        model.onShutdownBlocked = { [weak self] in self?.quitting = false }
        model.onCloseWindows = { [weak self] ids in for id in ids { self?.windows[id]?.close() } }
    }
    private func openWindow(_ requested: String? = nil) {
        let id = model.claimWindowID(requested)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.title = "Crest Control Plane · Chromium"
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: ControlPlaneWindow(
            model: model, restorationID: .constant(id),
            restoreAdditionalWindow: { [weak self] in self?.openWindow($0) }, preclaimedWindowID: id))
        windows[id] = window
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)),
            name: NSWindow.willCloseNotification, object: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    @objc private func windowClosed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = window.identifier?.rawValue else { return }
        windows.removeValue(forKey: id)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    }
    @objc(windowForIdentifier:)
    static func window(for identifier: String?) -> NSWindow? {
        guard let instance else { return nil }
        if let identifier { return instance.windows[identifier] }
        return instance.windows.values.first
    }
    @objc static func deferQuit() -> Bool {
        guard let instance, !instance.model.hasStopped else { return false }
        if !instance.quitting { instance.quitting = true; instance.model.shutdown() }
        return true
    }
    @objc static func handleShortcutEvent(_ event: NSEvent) -> Bool {
        guard let instance, event.type == .keyDown,
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
            let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if key == "q" { return deferQuit() }
        if instance.model.isPreparingShutdown { return ["n", "t", "w", "r"].contains(key) }
        if key == "n" { instance.openWindow(); return true }
        if key == "l" { focusOmnibox(); return true }
        guard let id = NSApp.keyWindow?.identifier?.rawValue, instance.windows[id] != nil else { return false }
        switch key {
        case "t": instance.model.command("core.new_tab", windowID: id)
        case "w":
            if instance.model.window(id)?.tabId != nil { instance.model.command("core.close_tab", windowID: id) }
            else { instance.windows[id]?.performClose(nil) }
        case "r": instance.model.command("core.reload", windowID: id)
        default: return false
        }
        return true
    }
    @objc static func showNativeNotice(_ message: String, icon: String) { instance?.model.error = message }
    @objc static func focusOmnibox() {
        guard let window = NSApp.keyWindow else { return }
        func addressField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.placeholderString == "Address" { return field }
            return view.subviews.lazy.compactMap { addressField(in: $0) }.first
        }
        if let content = window.contentView, let field = addressField(in: content) {
            window.makeFirstResponder(field); field.selectText(nil)
        }
    }
    // BrowserWindow entry points remain explicit until their native UI is migrated.
    @objc static func toggleBookmark(forURL url: String, title: String) {
        guard let instance, let windowID = NSApp.keyWindow?.identifier?.rawValue,
            let tab = instance.model.tab(windowID), tab.url == url else { return }
        instance.model.command("core.place_tab", windowID: windowID,
            extra: ["tabId": tab.id, "placement": tab.placement == "current" ? "saved" : "current"])
    }
    @objc static func shareURL(_ url: String, title: String) {
        guard let item = URL(string: url), let view = NSApp.keyWindow?.contentView else { return }
        NSSharingServicePicker(items: [item]).show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }
    @objc static func showQRCode(forURL url: String, title: String) { showNativeNotice("QR sharing is not yet connected in this host.", icon: "qrcode") }
    @objc static func translateURL(_ url: String) { showNativeNotice("Translation is not yet connected in this host.", icon: "globe") }
    @objc static func translateText(_ text: String) { showNativeNotice("Translation is not yet connected in this host.", icon: "globe") }
    @objc static func showTabSearch() { focusOmnibox() }
}
#endif
