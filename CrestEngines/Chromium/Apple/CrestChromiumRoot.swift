#if CREST_CHROMIUM_HOST
import AppKit
import SwiftUI

/// Chromium owns the process and AppController. Crest owns the same window
/// composition, stores, and SwiftUI views used by its WebKit application.
@objc(CrestRoot) @MainActor
final class CrestChromiumRoot: NSObject, BrowserMacWindowPresenting {
    static let extensions = ChromiumExtensionStore()
    private static var instance: CrestChromiumRoot?
    static var engineHost: (any CrestChromiumEngineHost)? { instance?.host }
    private let host: any CrestChromiumEngineHost
    private let application: BrowserMacApplication
    private var downloads: ChromiumDownloadAdapter?
    private var windows: [BrowserWindowID: NSWindow] = [:]
    private var quickWindows: [UUID: QuickWindow] = [:]
    private final class QuickWindow {
        let window: CrestChromiumWindow
        let model: BrowserQuickWindowModel
        let request: QuickRequest
        init(window: CrestChromiumWindow, model: BrowserQuickWindowModel, request: QuickRequest) {
            self.window = window; self.model = model; self.request = request
        }
    }
    private final class QuickRequest {
        var value: BrowserQuickWindowRequest
        init(_ value: BrowserQuickWindowRequest) { self.value = value }
    }
    private struct QuickWindowTitle: ViewModifier {
        let model: BrowserQuickWindowModel
        let request: QuickRequest
        weak var window: NSWindow?

        func body(content: Content) -> some View {
            content.onChange(of: model.windowTitle(for: request.value), initial: true) { _, title in
                window?.title = title
            }
        }
    }
    private var privateWindow: NSWindow?
    private var privateSourceProfile: UUID?
    static var privateSourceProfileID: UUID? { instance?.privateSourceProfile }
    private var eventMonitor: Any?
    private var browserMenu: CrestChromiumMenu?
    private var quitting = false
    private var hasStopped = false

    @objc(startWithHost:)
    static func start(host: any CrestChromiumEngineHost) {
        guard instance == nil else { return }
        let root = CrestChromiumRoot(host: host)
        instance = root
        BrowserMacWindowPresentation.host = root
        BrowserMacAppIconPreference.restore()
        root.openWindow(.initial)
        root.browserMenu = CrestChromiumMenu(shortcuts: root.application.shortcuts,
            actions: { [weak root] in root?.actions },
            perform: { [weak root] in root?.perform($0) },
            canPerform: { [weak root] in root?.canPerform($0) == true },
            applicationAction: { [weak root] in root?.performApplicationAction($0) },
            canCheckForUpdates: { [weak root] in root?.application.softwareUpdates.isEnabled == true })
        root.browserMenu?.install()
        Task { await root.application.cloudSync.start() }
        root.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleShortcutEvent(event) ? nil : event
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(host: any CrestChromiumEngineHost) {
        self.host = host
        application = BrowserMacApplication(pageClosePreparation: ChromiumPageClosePreparer(host: host))
        super.init()
        downloads = ChromiumDownloadAdapter(host: host) { [weak self] values, profileID in
            guard let self else { return nil }
            var contexts = self.windows.keys.compactMap { id -> (BrowserStore, BrowserPagePool)? in
                guard let model = self.application.windowCoordinator.existingModel(for: id) else { return nil }
                return (model.browser, model.pages)
            }
            if self.privateWindow != nil { contexts.append((self.application.privateBrowser, self.application.privatePages)) }
            for (browser, pages) in contexts {
                let assignment: BrowserSpaceRuntimeAssignment?
                if let pageID = values["sourcePageId"] as? String {
                    assignment = pages.chromiumDownloadAssignment(pageID: pageID, profileID: profileID)
                } else {
                    // Background extension downloads have no page. Only route a
                    // uniquely owned profile; never borrow the selected Space.
                    let spaces = browser.session.spaces.filter { $0.profile.id == profileID }
                    assignment = spaces.count == 1 ? BrowserSpaceRuntimeAssignment(space: spaces[0]) : nil
                }
                guard let assignment, let space = browser.space(matching: assignment),
                    !self.application.spaceAccess.isLocked(space) else { continue }
                return ChromiumDownloadAdapter.Destination(center: pages.downloadCenter, assignment: assignment)
            }
            return nil
        }
        host.setExtensionReview { values, window, reply in
            MainActor.assumeIsolated { Self.extensions.review(values, window: window, reply: reply) }
        }
        host.setBrowserObserver { [weak self] values in
            MainActor.assumeIsolated {
                let values = ChromiumInternalURL.presentedValues(values)
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
        guard let destination = URL(string: ChromiumInternalURL.presented(url.absoluteString)),
              model.browser.openNewTab(url: destination, matching: BrowserSpaceRuntimeAssignment(space: space)) != nil else { return false }
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

    func openQuickWindow(_ request: BrowserQuickWindowRequest) {
        if let existing = quickWindows.values.first(where: { $0.request.value == request }) {
            existing.window.makeKeyAndOrderFront(nil); return
        }
        let resolver = BrowserQuickWindowContextResolver(browser: application.browser,
            pages: application.pages, pagePoolRegistry: application.pagePoolRegistry)
        guard let context = resolver.context(for: request),
            let space = context.browser.space(matching: request.assignment), !application.spaceAccess.isLocked(space) else { return }
        let current = QuickRequest(request)
        let model = BrowserQuickWindowModel(request: request, browser: context.browser, pages: context.pages,
            spaceAccess: application.spaceAccess, supportsLivePagePromotion: context.supportsLivePagePromotion,
            preferences: .production, requestLifecycle: BrowserQuickWindowRequestLifecycle(
                isCurrent: { [weak current] in current?.value.hasSamePresentationIdentity(as: $0) == true },
                replace: { [weak current] expected, revised in
                    guard let current, current.value.hasSamePresentationIdentity(as: expected) else { return false }
                    current.value = revised; return true
                }))
        let window = CrestChromiumWindow(contentRect: NSRect(x: 0, y: 0, width: BrowserQuickWindowLayout.defaultWidth,
            height: BrowserQuickWindowLayout.defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(request.id.uuidString)
        window.title = "Quick Window"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.approveClose = { [weak self, weak window] completion in
            guard let self, let window else { completion(false); return }
            self.prepareWindowClose(window, completion: completion)
        }
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: BrowserQuickWindowLayout.minimumWidth, height: BrowserQuickWindowLayout.minimumHeight)
        quickWindows[request.id] = QuickWindow(window: window, model: model, request: current)
        window.contentViewController = NSHostingController(rootView: BrowserQuickWindowWindowSurface(
            model: model, spaceAccess: application.spaceAccess, pagePoolRegistry: application.pagePoolRegistry,
            dismiss: { [weak window] in window?.performClose(nil) },
            openBrowserWindow: { [weak self] in
                guard let self else { return }
                if !self.application.windowCoordinator.activateExistingWindow(for: context.browser) {
                    self.openWindow(.normal(sourceWindowID: request.targetWindowID))
                }
            }).environment(application.windowTransparency).environment(application.splitFocus)
            .environment(application.softwareUpdates)
            .modifier(QuickWindowTitle(model: model, request: current, window: window)))
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)),
            name: NSWindow.willCloseNotification, object: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func openPrivateWindow() {
        if let privateWindow { privateWindow.makeKeyAndOrderFront(nil); return }
        guard let source = activeModel?.browser.selectedSpace?.profile.id
            ?? application.browser.selectedSpace?.profile.id else { return }
        privateSourceProfile = source
        let window = CrestChromiumWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        privateWindow = window
        application.pagePoolRegistry.register(application.privatePages, browser: application.privateBrowser,
            for: application.privatePages.windowID)
        window.identifier = NSUserInterfaceItemIdentifier(application.privatePages.windowID.rawValue.uuidString)
        window.title = "Private Browsing"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.approveClose = { [weak self, weak window] completion in
            guard let self, let window else { completion(false); return }
            self.prepareWindowClose(window, completion: completion)
        }
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.contentViewController = NSHostingController(rootView: application.privateWindowContent)
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)),
            name: NSWindow.willCloseNotification, object: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func openWindow(_ request: BrowserMacWindowRequest) {
        if let existing = windows[request.id] { existing.makeKeyAndOrderFront(nil); return }
        guard application.windowCoordinator.model(for: request) != nil else { return }
        let window = CrestChromiumWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(request.id.rawValue.uuidString)
        window.title = "Crest"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 720, height: 500)
        window.approveClose = { [weak self, weak window] completion in
            guard let self, let window else { completion(false); return }
            self.prepareWindowClose(window, completion: completion)
        }
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

    private func prepareWindowClose(_ window: NSWindow, completion: @escaping (Bool) -> Void) {
        guard !quitting, let id = window.identifier?.rawValue else { completion(false); return }
        var ids = [id]
        if window === privateWindow {
            ids += quickWindows.values.filter { $0.model.browser.isPrivateBrowsing }
                .compactMap { $0.window.identifier?.rawValue }
        }
        host.prepareToClose(pages: [], windows: ids, completion: completion)
    }

    @objc private func windowClosed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let id = quickWindows.first(where: { $0.value.window === window })?.key,
            let quick = quickWindows.removeValue(forKey: id) {
            quick.model.releaseForDismissal()
            window.contentViewController = nil
            host.disposePages([], windows: [id.uuidString], releaseProfiles: [])
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            return
        }
        if window === privateWindow {
            for quick in Array(quickWindows.values) where quick.model.browser.isPrivateBrowsing { quick.window.closeAfterApproval() }
            let profiles = application.privateBrowser.session.spaces.map { $0.profile.id.uuidString }
            application.pagePoolRegistry.unregister(application.privatePages, for: application.privatePages.windowID)
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
        if let identifier, let quick = instance.quickWindows.values.first(where: { $0.window.identifier?.rawValue == identifier }) {
            return quick.window
        }
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
                    for quick in Array(instance.quickWindows.values) { quick.window.closeAfterApproval() }
                    for id in Array(instance.windows.keys) {
                        guard let model = instance.application.windowCoordinator.existingModel(for: id) else { continue }
                        model.pages.archiveResidentTabStates()
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
            NSApp.modalWindow == nil, NSApp.keyWindow?.attachedSheet == nil,
            (NSApp.keyWindow?.firstResponder as? ShortcutRecorderButton)?.isRecording != true,
            let shortcut = BrowserShortcut(event: event), shortcut.isValid else { return false }
        if shortcut == BrowserShortcut(key: .character("q"), modifiers: .command) { return deferQuit() }
        guard !instance.quitting else { return true }
        if shortcut == BrowserShortcut(key: .character(","), modifiers: .command) {
            instance.performApplicationAction(.settings)
            return true
        }
        // Inspector, extension popup and system dialog responders are not a
        // browser workspace. Their editing and close shortcuts stay local.
        guard instance.activeContext != nil || instance.quickWindows.values.contains(where: { $0.window === NSApp.keyWindow }) else { return false }
        guard let command = instance.application.shortcuts.command(for: event, isEnabled: instance.canPerform) else { return false }
        instance.perform(command)
        return true
    }

    private func canPerform(_ command: BrowserShortcutCommand) -> Bool {
        guard !quitting, NSApp.modalWindow == nil, NSApp.keyWindow?.attachedSheet == nil else { return false }
        switch command {
        // These page services still need Chromium adapters. Do not send them
        // to a nonexistent WebKit document or a disconnected SwiftUI scene.
        case .toggleContentBlocking, .toggleTranslationToolbar,
             .exportPDF, .saveWebArchive, .printPage: return false
        case .newWindow, .newPrivateWindow: return true
        case .closeWindow, .closeTabOrWindow:
            return actions != nil || quickWindows.values.contains(where: { $0.window === NSApp.keyWindow })
        default: return actions?.canPerform(command) == true
        }
    }

    private func perform(_ command: BrowserShortcutCommand) {
        guard canPerform(command) else { return }
        if let actions { actions.perform(command); return }
        switch command {
        case .newWindow: openWindow(.normal(sourceWindowID: nil))
        case .newPrivateWindow: openPrivateWindow()
        case .closeWindow, .closeTabOrWindow: NSApp.keyWindow?.performClose(nil)
        default: break
        }
    }

    private func performApplicationAction(_ action: CrestChromiumMenu.ApplicationAction) {
        switch action {
        case .about:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "Crest", .applicationVersion: version,
                .credits: NSAttributedString(string: "Chromium \(host.engineVersion())"),
                .applicationIcon: NSApp.applicationIconImage as Any])
        case .updates: application.softwareUpdates.checkForUpdates()
        case .settings, .gettingStarted:
            if activeContext == nil { openWindow(.normal(sourceWindowID: nil)) }
            guard let context = activeContext else { return }
            if action == .settings { context.browser.openSettings() }
            else { context.browser.openGettingStarted() }
            context.pages.select(session: context.browser.session)
        }
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
