#if CREST_CHROMIUM_HOST
import AppKit
import SwiftUI

/// Chromium owns the process and AppController. Crest owns the same window
/// composition, stores, and SwiftUI views used by its WebKit application.
@objc(CrestRoot) @MainActor
final class CrestChromiumRoot: NSObject, BrowserMacWindowPresenting {
    static let extensions = ChromiumExtensionStore()
    private static var instance: CrestChromiumRoot?
    private static var recoveryWindow: NSWindow?
    private static var recoveryKeyMonitor: Any?
    private static var launch: BrowserApplicationLaunch<CrestChromiumRoot>?
    private struct RecoveryContent: View {
        let launch: BrowserApplicationLaunch<CrestChromiumRoot>

        var body: some View {
            BrowserSessionRecoveryView(launch: launch)
                .onChange(of: launch.value != nil, initial: true) {
                    if let root = launch.value { CrestChromiumRoot.finishStart(root) }
                }
        }
    }
    static var engineHost: (any CrestChromiumEngineHost)? { instance?.host }
    /// External URLs delivered before the root owns a window. Chromium hands
    /// them over during startup, which can be while session recovery is still
    /// on screen; they open once the first window exists.
    private static var pendingExternalURLs: [URL] = []
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
    private var onboardingWindow: NSWindow?
    private var privateWindow: NSWindow?
    private var privateSourceProfile: UUID?
    static var privateSourceProfileID: UUID? { instance?.privateSourceProfile }
    private var eventMonitor: Any?
    private var browserMenu: CrestChromiumMenu?
    private var quitting = false
    private var hasStopped = false
    /// Which normal windows were open, newest last. Window contents and
    /// selection stay in `BrowserWindowStateStore`, and frames stay in AppKit's
    /// own autosave records; this list only records how many windows the
    /// SwiftUI `WindowGroup` would have restored, which AppKit cannot tell a
    /// framework-hosted window itself.
    private var restorableWindowIDs: [BrowserWindowID] = []
    private let restorationDefaults: UserDefaults?
    private static let restorableWindowsKey = "crest.chromium.windows.v1"

    @objc(startWithHost:)
    static func start(host: any CrestChromiumEngineHost) {
        guard instance == nil, launch == nil else { return }
        let launch = BrowserApplicationLaunch { try CrestChromiumRoot(host: host) }
        Self.launch = launch
        if let root = launch.value { finishStart(root); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 380),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Crest Recovery"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RecoveryContent(launch: launch))
        recoveryWindow = window
        let menu = NSMenu()
        let item = NSMenuItem()
        let applicationMenu = NSMenu(title: ProductIdentity.name)
        let quit = NSMenuItem(title: "Quit Crest", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        applicationMenu.addItem(quit)
        item.submenu = applicationMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        recoveryKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers == "q" {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func finishStart(_ root: CrestChromiumRoot) {
        guard instance == nil else { return }
        instance = root
        BrowserMacWindowPresentation.host = root
        BrowserMacAppIconPreference.restore()
        root.restoreWindows()
        if let recoveryKeyMonitor { NSEvent.removeMonitor(recoveryKeyMonitor) }
        recoveryKeyMonitor = nil
        recoveryWindow?.close()
        recoveryWindow = nil
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
        root.openPendingExternalURLs()
    }

    private init(host: any CrestChromiumEngineHost) throws {
        self.host = host
        application = try BrowserMacApplication(pageClosePreparation: ChromiumPageClosePreparer(host: host),
            profileRemover: ChromiumProfileRemover(host: host))
        restorationDefaults = Self.restorationDefaults()
        restorableWindowIDs = Self.storedRestorableWindowIDs(in: restorationDefaults)
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
                if let profileID = values["deletedProfile"] as? String {
                    Self.extensions.refresh()
                    if self?.privateSourceProfile?.uuidString == profileID { self?.privateWindow?.close() }
                    return
                }
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
        return instance.application.browser.session.spaces.filter {
            !instance.application.browser.deletingSpaceIDs.contains($0.id) && !instance.application.spaceAccess.isLocked($0)
        }
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

    func openOnboardingWindow(_ request: BrowserOnboardingRequest) {
        if let onboardingWindow {
            // Reopening setup brings its current draft forward.
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let source = activeModel
        let browser = source?.browser ?? application.browser
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(BrowserOnboardingCoordinator.sceneID)
        window.title = BrowserOnboardingWindowActivation.windowTitle
        window.contentMinSize = NSSize(width: 980, height: 660)
        window.isReleasedWhenClosed = false
        // Match the SwiftUI scene's hidden title bar before the first layout.
        // The shared onboarding configurator applies the same settings, but it
        // only runs once its view reaches a window, which is after this window
        // has already laid its content out under an opaque title bar.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        onboardingWindow = window
        let content = NSHostingController(rootView: BrowserOnboardingWindow(
            request: request, browser: browser, cloudSync: application.cloudSync,
            progress: application.onboardingProgress, spaceAccess: application.spaceAccess,
            hostClose: { [weak window] in window?.close() },
            hostOpenBrowser: { [weak self] in
                guard let self else { return }
                if let id = source?.id, let browserWindow = self.windows[id] { browserWindow.makeKeyAndOrderFront(nil) }
                else { self.openWindow(.normal(sourceWindowID: nil)) }
            }))
        // A hosting controller reports its content's ideal size as the window's
        // preferred content size by default, and the setup content is fully
        // flexible above its 980-by-660 minimum. AppKit would therefore shrink
        // this window to that minimum, leaving the preview panes flush with the
        // window edge instead of the 1180-by-820 layout the SwiftUI scene opens
        // with. Let the requested content rect stand instead.
        content.sizingOptions = []
        window.contentViewController = content
        window.setContentSize(NSSize(width: 1180, height: 820))
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)),
            name: NSWindow.willCloseNotification, object: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Restoration

    /// The defaults domain this launch persists window state into. It mirrors
    /// `BrowserMacApplication`'s own choice so an isolated session keeps its
    /// window list beside the rest of its state.
    private static func restorationDefaults() -> UserDefaults? {
        let environment = BrowserLaunchEnvironment.current
        guard BrowserLaunchIsolationPolicy.requiresIsolation(environment) else { return .standard }
        guard let isolationID = environment.persistentIsolationID else { return nil }
        return UserDefaults(suiteName: BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(isolationID: isolationID))
    }

    private static func storedRestorableWindowIDs(in defaults: UserDefaults?) -> [BrowserWindowID] {
        guard let stored = defaults?.array(forKey: restorableWindowsKey) as? [String] else { return [] }
        return stored.compactMap(UUID.init(uuidString:)).map(BrowserWindowID.init(rawValue:))
    }

    private func persistRestorableWindowIDs() {
        restorationDefaults?.set(restorableWindowIDs.map { $0.rawValue.uuidString }, forKey: Self.restorableWindowsKey)
    }

    /// Reopens the normal windows the previous session left open. Private and
    /// Quick Windows are deliberately not restored.
    private func restoreWindows() {
        let restored = restorableWindowIDs
        restorableWindowIDs = []
        for id in restored { openWindow(id == .main ? .initial : BrowserMacWindowRequest(id: id, kind: .normal)) }
        if windows.isEmpty { openWindow(.initial) }
        let front = restored.first { windows[$0] != nil } ?? windows.keys.first
        if let front, let window = windows[front] { window.makeKeyAndOrderFront(nil) }
    }

    /// A Dock click or `Open` with no Crest window. The SwiftUI application
    /// brings an existing window forward and otherwise opens the initial
    /// window; Chromium must not create a browser of its own here because it
    /// would have no registered native window.
    @objc static func reopen() -> Bool {
        guard let instance, !instance.quitting else { return false }
        if let window = activeNativeWindow ?? instance.privateWindow
            ?? instance.quickWindows.values.first?.window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            instance.openWindow(.initial)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    // MARK: - External URLs

    /// Chromium's `AppController` hands over every external open. Routing then
    /// matches the SwiftUI application's own external-link handling.
    @objc(openExternalURLs:)
    static func openExternalURLs(_ urls: [URL]) -> Bool {
        let accepted = urls.filter {
            $0.isFileURL
                ? BrowserExternalURLPolicy.acceptsLocalDocument($0)
                : BrowserExternalURLPolicy.accepts($0)
        }
        guard !accepted.isEmpty else { return true }
        guard let instance else {
            pendingExternalURLs.append(contentsOf: accepted)
            return true
        }
        instance.openExternalURLs(accepted)
        return true
    }

    private func openPendingExternalURLs() {
        let pending = Self.pendingExternalURLs
        Self.pendingExternalURLs = []
        guard !pending.isEmpty else { return }
        openExternalURLs(pending)
    }

    private func openExternalURLs(_ urls: [URL]) {
        Task { @MainActor in
            let documents = urls.filter { $0.isFileURL }
            if !documents.isEmpty { await openLocalDocuments(documents) }
            for url in urls where !url.isFileURL { await openExternalURL(url) }
        }
    }

    /// The window an external open belongs to. A tear-off window owns a
    /// disposable workspace, so it never receives one; if no normal window is
    /// left, one opens. An external open rarely arrives while Crest is
    /// frontmost, so there is usually no key window to ask.
    private func externalTargetModel() -> BrowserMacWindowModel? {
        let active = activeModel.flatMap { $0.isTemporary ? nil : $0 }
        if active == nil, restorableWindowIDs.isEmpty { openWindow(.initial) }
        return active ?? restorableWindowIDs.reversed().lazy
            .compactMap({ self.application.windowCoordinator.existingModel(for: $0) }).first
    }

    /// A document opened from Finder, Open With or `open -a Crest` is not a web
    /// link and has no host to route on. It belongs in the Space on screen.
    private func openLocalDocuments(_ urls: [URL]) async {
        guard let model = externalTargetModel(), let space = model.browser.selectedSpace else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard await application.spaceAccess.unlock(space),
            model.browser.space(matching: assignment) != nil else { return }
        BrowserCommandActions(browser: model.browser, pages: model.pages, chrome: model.chrome,
            openWindow: EnvironmentValues().openWindow, spaceAccess: application.spaceAccess,
            targetWindowID: model.id).openLocalDocuments(urls, in: assignment)
        windows[model.id]?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openExternalURL(_ url: URL) async {
        guard let model = externalTargetModel() else { return }
        let browser = model.browser
        let decision = BrowserLinkPreferenceStore.shared.routingDecision(
            for: url, in: browser.session, unavailableSpaceIDs: browser.deletingSpaceIDs)
        guard let space = browser.session.space(id: decision.spaceID) else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard await application.spaceAccess.unlock(space), browser.space(matching: assignment) != nil else { return }
        switch decision {
        case .quickWindow:
            openQuickWindow(BrowserQuickWindowRequest(url: url, spaceAssignment: assignment, targetWindowID: model.id))
        case .space:
            guard browser.openNewTab(url: url, matching: assignment) != nil else { return }
            model.pages.select(session: browser.session)
            model.pages.load(url)
            model.chrome.dismissCommandPalette()
            windows[model.id]?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
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
        if request.kind == .normal {
            // Frames belong to AppKit's autosave records, as they do for the
            // SwiftUI scene. Tear-off windows keep their drop placement.
            let autosaveName = "crest.chromium.window.\(request.id.rawValue.uuidString)"
            if !window.setFrameUsingName(autosaveName) { window.center() }
            window.setFrameAutosaveName(autosaveName)
            restorableWindowIDs.removeAll { $0 == request.id }
            restorableWindowIDs.append(request.id)
            persistRestorableWindowIDs()
        } else {
            window.center()
        }
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
        if window === onboardingWindow {
            onboardingWindow = nil
            window.contentViewController = nil
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            return
        }
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
        // A window the user closed is not restored; windows still open at quit
        // are, so a terminating application keeps its recorded list.
        if !quitting, restorableWindowIDs.contains(id) {
            restorableWindowIDs.removeAll { $0 == id }
            persistRestorableWindowIDs()
        }
        application.windowCoordinator.closeWindow(id)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
    }

    // MARK: - Engine-created windows

    /// Reserves the Crest window that will host a Browser the engine created
    /// for itself — `chrome.windows.create`, an extension app window — and
    /// names the Space its tabs belong to.
    ///
    /// Nothing is presented here: the engine creates the Browser first and
    /// offers its tabs afterwards, and a renderer popup keeps its opener's
    /// window instead. A profile with no Space to host it is declined, so the
    /// engine drops those tabs rather than routing them into an unrelated
    /// Space. An off-the-record profile belongs to the private window and is
    /// declined outright when that window is closed.
    @objc(reserveEngineWindowForProfile:)
    static func reserveEngineWindow(forProfile profileID: String) -> [String: String]? {
        guard let instance, !instance.quitting, let profile = UUID(uuidString: profileID) else { return nil }
        if let space = instance.application.privateBrowser.session.spaces.first(where: { $0.profile.id == profile }) {
            guard let identifier = instance.privateWindow?.identifier?.rawValue else { return nil }
            return ["windowId": identifier, "spaceId": space.id.rawValue.uuidString]
        }
        guard let space = extensionSpaces.first(where: { $0.profile.id == profile }) else { return nil }
        return ["windowId": BrowserWindowID().rawValue.uuidString, "spaceId": space.id.rawValue.uuidString]
    }

    /// Opens the window reserved for an engine-created Browser, just before its
    /// first tab is offered for adoption.
    @objc(presentEngineWindow:space:focused:)
    static func presentEngineWindow(_ windowID: String, space spaceID: String, focused: Bool) {
        guard let instance, !instance.quitting, let identifier = UUID(uuidString: windowID),
            let space = UUID(uuidString: spaceID).map(SpaceID.init(rawValue:)) else { return }
        if let window = instance.privateWindow, window.identifier?.rawValue == windowID {
            if focused { window.makeKeyAndOrderFront(nil) }
            return
        }
        let id = BrowserWindowID(rawValue: identifier)
        if instance.windows[id] == nil { instance.openWindow(BrowserMacWindowRequest(id: id, kind: .normal)) }
        guard let window = instance.windows[id],
            let model = instance.application.windowCoordinator.existingModel(for: id) else { return }
        model.browser.selectSpace(space)
        if focused {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFront(nil)
        }
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
        instance.persistRestorableWindowIDs()
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
    @objc static func translateURL(_ url: String) {
        showNativeNotice(
            "Whole-page translation is not available in this engine. Select text on the page, then translate the selection.",
            icon: "globe"
        )
    }
    @objc static func translateText(_ text: String) { ChromiumSelectionTranslation.present(text) }
    @objc static func showTabSearch() { instance?.activeContext?.chrome.presentCommandPalette() }
}
#endif
