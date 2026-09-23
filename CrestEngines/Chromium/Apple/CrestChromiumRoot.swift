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
    /// The browser operations engine requests run through.
    static var hostCommands: (any BrowserEngineHostCommands)? { instance?.application }
    private var commands: any BrowserEngineHostCommands { application }
    /// External URLs delivered before the root owns a window. Chromium hands
    /// them over during startup, which can be while session recovery is still
    /// on screen; they open once the first window exists.
    private static var pendingExternalURLs: [URL] = []
    private static var pendingAuthenticationSessions: [(url: URL, id: UUID)] = []
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
        // The Dock plug-in runs outside the browser process, including after quit.
        // App artwork uses the isolated app's domain, not an environment-only
        // browsing profile name that the Dock cannot discover.
        BrowserMacAppIconPreference.defaults = .standard
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
        root.openPendingAuthenticationSessions()
    }

    private init(host: any CrestChromiumEngineHost) throws {
        self.host = host
        let pageEngines = ChromiumPageEngines()
        application = try BrowserMacApplication(pageClosePreparation: ChromiumPageClosePreparer(host: host),
            profileRemover: ChromiumProfileRemover(host: host),
            makePageEngine: { pageEngines.make(profileID: $0) },
            // Site Controls is where a keyboard-triggered extension popup opens
            // when the extension has no pinned tile to anchor to.
            siteControlAnchor: BrowserSiteControlAnchor {
                let anchor = BrowserExtensionPopupAnchorView()
                anchor.site = .menu
                return anchor
            },
            reviewPersistenceID: "chromium-native-ui-review")
        pageEngines.hostCommands = application
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
                    assignment = pages.engineDownloadAssignment(pageID: pageID, profileID: profileID)
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
                guard let adoption = BrowserEnginePageAdoption(chromiumValues: values) else {
                    host.rejectAdoption(token)
                    return
                }
                for id in self.windows.keys {
                    if self.application.windowCoordinator.existingModel(for: id)?.pages.adoptEnginePage(adoption) == true { return }
                }
                if self.privateWindow != nil, self.application.privatePages.adoptEnginePage(adoption) { return }
                host.rejectAdoption(token)
            }
        }
    }

    static var extensionSpaces: [BrowserSpace] { hostCommands?.extensionSpaces ?? [] }
    /// Whether this store is one of the persistent Spaces' own stores.
    ///
    /// Engine extension profiles belong to the application's persistent store
    /// family — every normal window's store shares it. A private window and a
    /// borrowed settings workspace each have a family of their own and no
    /// persistent engine profile, so neither may prepare or read one.
    static func ownsExtensionProfiles(_ browser: BrowserStore) -> Bool {
        guard let instance else { return false }
        return browser.family === instance.application.browser.family
            && !browser.isPrivateBrowsing && !browser.isTemporaryWorkspace
    }
    static func isSpaceLocked(_ space: BrowserSpace) -> Bool {
        guard let instance else { return true }
        return instance.application.browser.deletingSpaceIDs.contains(space.id)
            || instance.application.spaceAccess.isLocked(space)
    }
    static var activeNativeWindow: NSWindow? {
        guard let instance else { return nil }
        if let window = NSApp.keyWindow, instance.windows.values.contains(where: { $0 === window }) { return window }
        return instance.windows.values.first { $0.isMainWindow } ?? instance.windows.values.first
    }
    static func openExtensionURL(_ url: URL, in space: BrowserSpace, window: NSWindow) -> Bool {
        guard let instance, let id = instance.windows.first(where: { $0.value === window })?.key,
              let destination = URL(string: ChromiumInternalURL.presented(url.absoluteString)) else { return false }
        // Settings and extension options are core-owned tabs even when no web
        // page is active. Do not fabricate an opener or borrow another Space.
        return instance.commands.openTab(destination, in: BrowserSpaceRuntimeAssignment(space: space), window: id)
    }

    static func openExtensionSettings() {
        guard let instance, let model = instance.activeModel, let space = model.browser.selectedSpace,
              !instance.application.spaceAccess.isLocked(space) else { return }
        instance.commands.openExtensionSettings(for: BrowserSpaceRuntimeAssignment(space: space), in: model.id)
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
            }).environment(application.windowTransparency)
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
        guard environment.requiresIsolation else { return .standard }
        guard let isolationID = environment.persistentIsolationID else { return nil }
        return UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID))
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
                ? BrowserCorePolicy.acceptsLocalDocument($0)
                : BrowserCorePolicy.acceptsExternalURL($0)
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

    /// Where a link from another app lands: the window that receives it, the
    /// Space its routing names, and whether it opens as a Quick Window.
    private func externalDestination(for url: URL) async
        -> (model: BrowserMacWindowModel, assignment: BrowserSpaceRuntimeAssignment, decision: BrowserLinkRoutingDecision)? {
        guard let model = externalTargetModel() else { return nil }
        let browser = model.browser
        let decision = BrowserLinkPreferenceStore.shared.routingDecision(
            for: url, in: browser.session, unavailableSpaceIDs: browser.deletingSpaceIDs)
        // A link that arrived from another process never raises the biometric
        // prompt for a locked Space; it opens in a Quick Window on an unlocked one.
        guard let destination = BrowserExternalLinkLockPolicy.destination(
            routedTo: decision.spaceID, selectedSpaceID: browser.selectedSpace?.id,
            spaces: browser.session.spaces, unavailableSpaceIDs: browser.deletingSpaceIDs,
            isLocked: application.spaceAccess.isLocked) else { return nil }
        let space = destination.space
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard await application.spaceAccess.unlock(space), browser.space(matching: assignment) != nil else { return nil }
        let effective: BrowserLinkRoutingDecision =
            destination.substitutesForLockedSpace ? .quickWindow(spaceID: space.id) : decision
        return (model, assignment, effective)
    }

    private func openExternalURL(_ url: URL) async {
        guard let (model, assignment, effective) = await externalDestination(for: url) else { return }
        let browser = model.browser
        switch effective {
        case .quickWindow:
            openQuickWindow(BrowserQuickWindowRequest(url: url, spaceAssignment: assignment, targetWindowID: model.id))
        case .space:
            guard commands.openExternalLink(url, in: assignment, window: model.id) else { return }
            windows[model.id]?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - System sign-in

    /// An app's `ASWebAuthenticationSession` sign-in. It lands in the Space a
    /// link from that app routes to, always as a Quick Window: the session is
    /// transient and the engine closes the window when the page reaches the
    /// app's callback. `window` names the Quick Window so the engine can match
    /// the page to its request.
    @objc(openAuthenticationSession:window:)
    static func openAuthenticationSession(_ url: URL, window: String) -> Bool {
        guard let id = UUID(uuidString: window), BrowserCorePolicy.acceptsExternalURL(url) else { return false }
        guard let instance else {
            pendingAuthenticationSessions.append((url, id))
            return true
        }
        instance.openAuthenticationSession(url, id: id)
        return true
    }

    @objc(closeAuthenticationSession:)
    static func closeAuthenticationSession(_ window: String) {
        guard let instance, let id = UUID(uuidString: window) else { return }
        // The sign-in is over; a before-unload prompt would only get in the way.
        instance.quickWindows[id]?.window.closeAfterApproval()
    }

    private func openPendingAuthenticationSessions() {
        let pending = Self.pendingAuthenticationSessions
        Self.pendingAuthenticationSessions = []
        for (url, id) in pending { openAuthenticationSession(url, id: id) }
    }

    private func openAuthenticationSession(_ url: URL, id: UUID) {
        Task { @MainActor in
            guard let (model, assignment, _) = await externalDestination(for: url) else {
                host.cancelAuthenticationSession(window: id.uuidString)
                return
            }
            openQuickWindow(BrowserQuickWindowRequest(id: id, url: url, spaceAssignment: assignment, targetWindowID: model.id))
            guard let window = quickWindows[id]?.window else {
                host.cancelAuthenticationSession(window: id.uuidString)
                return
            }
            window.makeKeyAndOrderFront(nil)
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
            commands.closePrivateBrowsing()
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
    /// declined outright when that window is closed. A Space that is locked or
    /// being deleted is declined as well, so engine-created tabs never appear
    /// inside one the user has not unlocked.
    @objc(reserveEngineWindowForProfile:)
    static func reserveEngineWindow(forProfile profileID: String) -> [String: String]? {
        guard let instance, !instance.quitting, let profile = UUID(uuidString: profileID) else { return nil }
        // A profile belongs to exactly one Space. Resolve that Space instead of
        // accepting whichever one matched first, and refuse an ambiguous answer.
        func host(in browser: BrowserStore) -> BrowserSpace? {
            let owners = browser.session.spaces.filter { $0.profile.id == profile }
            guard owners.count == 1, let space = owners.first,
                !browser.deletingSpaceIDs.contains(space.id),
                !instance.application.spaceAccess.isLocked(space)
            else { return nil }
            return space
        }
        let privateBrowser = instance.application.privateBrowser
        if privateBrowser.session.spaces.contains(where: { $0.profile.id == profile }) {
            guard let space = host(in: privateBrowser),
                let identifier = instance.privateWindow?.identifier?.rawValue
            else { return nil }
            return ["windowId": identifier, "spaceId": space.id.rawValue.uuidString]
        }
        guard let space = host(in: instance.application.browser) else { return nil }
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
        guard let window = instance.windows[id] else { return }
        instance.commands.selectSpace(space, in: id)
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

    /// The panel host for the window that shows `window`'s page row, or `nil`
    /// for a window that has no row of its own: setup, a Quick Window or the
    /// recovery window.
    private static func sidePanelHost(for window: NSWindow) -> BrowserExtensionSidePanelHost? {
        guard let instance else { return nil }
        if let id = instance.windows.first(where: { $0.value === window })?.key {
            return BrowserExtensionSidePanelHosts.host(for: id)
        }
        guard instance.privateWindow === window else { return nil }
        return BrowserExtensionSidePanelHosts.host(for: instance.application.privatePages.windowID)
    }

    /// The engine asked for a side-panel card: `chrome.sidePanel.open()`,
    /// `chrome.sidePanel.close()`, or an action click whose extension opens a
    /// panel instead of a popup. The card belongs to the page's own window.
    @objc(routeSidePanel:page:request:)
    static func routeSidePanel(_ extensionID: String, page pageID: String,
                               request: CrestSidePanelRequest) {
        guard let instance, !instance.quitting, let page = ChromiumNativePage.live(pageID),
            let window = page.surface.window else { return }
        guard let host = sidePanelHost(for: window) else {
            // A Quick Window or setup page has no card row to hold a panel,
            // and a panel belongs to its page, so say where it can open.
            if request != .close {
                BrowserNoticeCenter.shared.post(BrowserNotice(
                    message: String(localized: "Side panels open in the main window. Open this page there to use it."),
                    systemImage: "sidebar.right"))
            }
            return
        }
        BrowserExtensionSidePanelHost.route(request, extensionID: extensionID, page: page, host: host)
    }

    /// The docked DevTools frontend for a page changed: it was opened, resized,
    /// moved to another dock side, or withdrawn. The page owns the card it is
    /// mounted in, so it reads the offer back itself.
    @objc(routeDevTools:)
    static func routeDevTools(_ pageID: String) {
        guard let instance, !instance.quitting else { return }
        ChromiumNativePage.live(pageID)?.refreshDevTools()
    }

    /// The inspector for a page is closing, whichever way it was closed.
    @objc(closeDevToolsPanel:)
    static func closeDevToolsPanel(_ pageID: String) {
        guard let instance, !instance.quitting else { return }
        ChromiumNativePage.live(pageID)?.developerPanelDidClose()
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
                        await instance.commands.flushPendingPersistence(in: id)
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
        if let command = instance.application.shortcuts.command(for: event, isEnabled: instance.canPerform) {
            instance.perform(command)
            return true
        }
        // Crest's own shortcuts win. What is left can belong to an extension's
        // `chrome.commands` binding in the active page's Space.
        return instance.dispatchExtensionShortcut(event)
    }

    /// Offers an unclaimed key equivalent to the extensions installed in the
    /// active page's own Space.
    private func dispatchExtensionShortcut(_ event: NSEvent) -> Bool {
        guard let page = activeContext?.pages.activePage?.chromiumPage,
            let result = host.dispatchExtensionShortcut(event, page: page.id) else { return false }
        // An `_execute_action` binding runs through the core so the popup keeps
        // the anchor a click on the extension's own button would have used: its
        // pinned tile, or the control that opens the window's extension list. A
        // shortcut has no pointer location, so the pointer is never the answer.
        if let extensionID = result["action"] as? String {
            page.runExtension(extensionID, anchor: BrowserExtensionToolbarAnchorRegistry.anchor(
                for: extensionID, in: page.surface.window))
        }
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
            if action == .settings { commands.openSettings(in: context.id) }
            else { commands.openGettingStarted(in: context.id) }
        }
    }

    /// Engine messages that ask nothing of the person — a toast, an action
    /// that could not run — are browser notices, never alerts.
    @objc static func showNativeNotice(_ message: String, icon: String) {
        BrowserNoticeCenter.shared.post(BrowserNotice(
            message: message, systemImage: NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil
                ? "info.circle" : icon))
    }
    @objc static func focusOmnibox() { instance?.actions?.openLocation() }
    @objc static func toggleBookmark(forURL url: String, title: String) { instance?.actions?.toggleSelectedTabPinned() }
    @objc static func shareURL(_ url: String, title: String) {
        guard let item = URL(string: url), let view = NSApp.keyWindow?.contentView else { return }
        NSSharingServicePicker(items: [item]).show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }
    @objc static func showQRCode(forURL url: String, title: String) { showNativeNotice("QR sharing is not yet connected in this host.", icon: "qrcode") }
    /// Chromium's own translate bubble asks for whole-page translation, which
    /// this adapter declares unavailable; the notice points at what is offered.
    @objc static func translateURL(_ url: String) {
        showNativeNotice(
            BrowserEngineRegistration.chromium.supports(.selectionTranslation)
                ? "Whole-page translation is not available in this engine. Select text on the page, then translate the selection."
                : "Translation is not available in this engine.",
            icon: "globe"
        )
    }
    @objc static func translateText(_ text: String) {
        guard BrowserEngineRegistration.chromium.supports(.selectionTranslation) else { return }
        ChromiumSelectionTranslation.present(text)
    }
    @objc static func showTabSearch() { instance?.activeContext?.chrome.presentCommandPalette() }
}
#endif
