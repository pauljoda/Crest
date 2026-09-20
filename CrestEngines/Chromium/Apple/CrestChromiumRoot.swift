#if CREST_CHROMIUM_HOST
import AppKit
import SwiftUI

/// Chromium owns the process and AppController. Crest owns the same window
/// composition, stores, and SwiftUI views used by its WebKit application.
@objc(CrestRoot) @MainActor
final class CrestChromiumRoot: NSObject {
    static let extensions = ChromiumExtensionStore()
    private static var instance: CrestChromiumRoot?
    static var engineHost: (any CrestChromiumEngineHost)? { instance?.host }
    private let host: any CrestChromiumEngineHost
    private let application: BrowserMacApplication
    private var windows: [BrowserWindowID: NSWindow] = [:]
    private var privateWindow: NSWindow?
    private var privateSourceProfile: UUID?
    static var privateSourceProfileID: UUID? { instance?.privateSourceProfile }
    private var eventMonitor: Any?
    private var quitting = false
    private var hasStopped = false

    @objc(startWithHost:)
    static func start(host: any CrestChromiumEngineHost) {
        guard instance == nil else { return }
        let root = CrestChromiumRoot(host: host)
        instance = root
        BrowserMacAppIconPreference.restore()
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
        host.setExtensionReview { values, window, reply in
            MainActor.assumeIsolated { Self.extensions.review(values, window: window, reply: reply) }
        }
        host.setBrowserObserver { [weak self] values in
            MainActor.assumeIsolated {
                if values["extensionsChanged"] as? Bool == true { Self.extensions.refresh(); return }
                guard let self, let token = values["adoptionId"] as? String else { return }
                for id in self.windows.keys {
                    if self.application.windowCoordinator.existingModel(for: id)?.pages.adoptChromiumPage(values) == true { return }
                }
                if self.privateWindow != nil, self.application.privatePages.adoptChromiumPage(values) { return }
                host.rejectAdoption(token)
            }
        }
    }

    static var extensionSpaces: [BrowserSpace] {
        guard let instance else { return [] }
        return instance.application.browser.session.spaces.filter { !instance.application.spaceAccess.isLocked($0) }
    }
    static var activeNativeWindow: NSWindow? {
        guard let instance else { return nil }
        if let window = NSApp.keyWindow, instance.windows.values.contains(where: { $0 === window }) { return window }
        return instance.windows.values.first { $0.isMainWindow } ?? instance.windows.values.first
    }
    static func openExtensionURL(_ url: URL, in space: BrowserSpace, window: NSWindow) -> Bool {
        guard let instance, let id = instance.windows.first(where: { $0.value === window })?.key,
              let model = instance.application.windowCoordinator.existingModel(for: id),
              model.browser.space(matching: BrowserSpaceRuntimeAssignment(space: space)) != nil,
              !instance.application.spaceAccess.isLocked(space) else { return false }
        // Settings and extension options are core-owned tabs even when no web
        // page is active. Do not fabricate an opener or borrow another Space.
        model.browser.selectSpace(space.id)
        guard model.browser.openNewTab(url: url, matching: BrowserSpaceRuntimeAssignment(space: space)) != nil else { return false }
        model.pages.select(session: model.browser.session)
        return true
    }

    static func openExtensionSettings() {
        guard let instance, let model = instance.activeModel, let space = model.browser.selectedSpace,
              !instance.application.spaceAccess.isLocked(space) else { return }
        model.spaceSettingsPresentation.present(.extensions, assignment: BrowserSpaceRuntimeAssignment(space: space))
        model.browser.openSettings()
        model.pages.select(session: model.browser.session)
    }

    static func openNativeWindow(_ request: BrowserMacWindowRequest) { instance?.openWindow(request) }

    static func openPrivateNativeWindow() { instance?.openPrivateWindow() }

    private func openPrivateWindow() {
        if let privateWindow { privateWindow.makeKeyAndOrderFront(nil); return }
        guard let source = activeModel?.browser.selectedSpace?.profile.id
            ?? application.browser.selectedSpace?.profile.id else { return }
        privateSourceProfile = source
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        privateWindow = window
        window.identifier = NSUserInterfaceItemIdentifier(application.privatePages.windowID.rawValue.uuidString)
        window.title = "Private Browsing"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.contentViewController = NSHostingController(rootView: application.privateWindowContent)
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)),
            name: NSWindow.willCloseNotification, object: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

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

    private var activeContext: (browser: BrowserStore, pages: BrowserPagePool, chrome: BrowserChromeState, id: BrowserWindowID)? {
        if let window = privateWindow, NSApp.keyWindow === window {
            return (application.privateBrowser, application.privatePages, application.privateChrome, application.privatePages.windowID)
        }
        guard let model = activeModel else { return nil }
        return (model.browser, model.pages, model.chrome, model.id)
    }

    private var actions: BrowserCommandActions? {
        guard let model = activeContext else { return nil }
        return BrowserCommandActions(browser: model.browser, pages: model.pages, chrome: model.chrome,
            openWindow: EnvironmentValues().openWindow, spaceAccess: application.spaceAccess, targetWindowID: model.id)
    }

    @objc private func windowClosed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === privateWindow {
            let profiles = application.privateBrowser.session.spaces.map { $0.profile.id.uuidString }
            application.closePrivateBrowsingWindow()
            host.disposePages([], windows: [application.privatePages.windowID.rawValue.uuidString], releaseProfiles: profiles)
            privateWindow = nil
            privateSourceProfile = nil
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            return
        }
        guard let id = windows.first(where: { $0.value === window })?.key else { return }
        windows.removeValue(forKey: id)
        application.windowCoordinator.closeWindow(id)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    }

    @objc(windowForIdentifier:)
    static func window(for identifier: String?) -> NSWindow? {
        guard let instance else { return nil }
        if let identifier, instance.privateWindow?.identifier?.rawValue == identifier { return instance.privateWindow }
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
            event.modifierFlags.contains(.command),
            let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == [.command, .shift], key == "n" { instance.openPrivateWindow(); return true }
        guard modifiers == .command || (modifiers == [.command, .shift] && key == "+") else { return false }
        if key == "q" { return deferQuit() }
        guard !instance.quitting else { return true }
        if key == "n" { instance.openWindow(.normal(sourceWindowID: instance.activeModel?.id)); return true }
        guard let model = instance.activeContext, let actions = instance.actions else { return false }
        switch key {
        case "l": actions.openLocation()
        case "t": actions.openNewTab()
        case "w": actions.closeTabOrWindow()
        case "r": model.pages.reloadOrStop(in: model.browser.session)
        case "f": model.pages.activePage?.presentFind()
        case "=", "+": _ = model.pages.activePage?.zoomIn()
        case "-": _ = model.pages.activePage?.zoomOut()
        case "0": _ = model.pages.activePage?.resetZoom()
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
    @objc static func showTabSearch() { instance?.activeContext?.chrome.presentCommandPalette() }
}
#endif
