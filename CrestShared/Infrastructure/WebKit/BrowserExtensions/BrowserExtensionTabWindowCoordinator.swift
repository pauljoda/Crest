import Foundation
import WebKit

struct BrowserExtensionControllerEntry {
    let controller: WKWebExtensionController
    let window: BrowserExtensionWindowAdapter
}

@MainActor
final class BrowserExtensionTabWindowCoordinator: NSObject {

    private let reportWindowFocus: (WKWebExtensionController, BrowserExtensionWindowAdapter?) -> Void
    let webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry

    var controllers: [SpaceID: BrowserExtensionControllerEntry] = [:]
    var tabsBySpace: [SpaceID: [TabID: BrowserExtensionTabAdapter]] = [:]
    var transientTabsBySpace: [SpaceID: [BrowserExtensionTransientTab]] = [:]
    var auxiliaryWindowsBySpace: [SpaceID: [BrowserExtensionWindowAdapter]] = [:]
    var auxiliaryWindowByTabID: [TabID: BrowserExtensionWindowAdapter] = [:]
    var auxiliaryPresentations: [ObjectIdentifier: any BrowserExtensionWindowPresentation] = [:]
    var pendingAuxiliaryWindow: BrowserExtensionWindowAdapter?
    var lastState: BrowserExtensionSessionState?
    weak var browser: (any BrowserExtensionTabWindowSessionHandling)?
    weak var pageProvider: (any BrowserExtensionPageProviding)?
    var openCommandSettings: ((BrowserExtensionCommandSettingsRoute, SpaceID) -> Bool)?
    var nativeMessagingHandler: BrowserExtensionNativeMessagingHandling?
    var sidebarService: (any BrowserExtensionSidebarHandling)?
    var tabGroupService: (any BrowserExtensionTabGroupHandling)?
    /// Holds the `modifyHeaders` request-header operations WebKit refuses, so
    /// every context of one extension applies the same table.
    var declarativeNetRequestService: (any BrowserExtensionDeclarativeNetRequestHandling)?
    /// Drops `SameSite` from the cookies of sites this extension's own pages
    /// frame, within the framing Space only.
    var cookieAccessService: (any BrowserExtensionCookieAccessHandling)?
    var sidebarLayoutSide: () -> String = { "right" }
    var sidebarUserGestures = BrowserExtensionUserGestureLedger()
    var sidebarClientsByContext: [ObjectIdentifier: BrowserExtensionServiceClientID] = [:]
    var debuggerService: (any BrowserExtensionDebuggerHandling)?
    /// Resolves the user's `debugger` decision for one extension, asking when
    /// the decision is still `.ask`. Supplied by the platform shell that owns
    /// the prompt; absent means no attachment is ever authorized.
    var debuggerConsent: (@MainActor (BrowserExtensionDebuggerIdentity) async -> Bool)?
    var debuggerClientsByContext: [ObjectIdentifier: BrowserExtensionServiceClientID] = [:]
    var debuggerIdentitiesByClient: [BrowserExtensionServiceClientID: BrowserExtensionDebuggerIdentity] = [:]
    /// Live `session token -> bound tab` records. See
    /// `BrowserExtensionDebuggerBrokerRequest` for why the binding is made once.
    var debuggerBindings: [String: BrowserExtensionDebuggerBinding] = [:]
    var verifiedNativeMessagingIdentities: [ObjectIdentifier: BrowserExtensionNativeMessagingIdentity] = [:]
    var verifiedNativeMessagingAuthorizations: [ObjectIdentifier: BrowserExtensionNativeMessagingAuthorization] = [:]
    #if os(macOS)
        var pendingActionPopupRequests: [ObjectIdentifier: BrowserExtensionActionPopupRequest] = [:]
        var popupBackgroundWarmUpObservers: [ObjectIdentifier: [BrowserExtensionPopupBackgroundWarmUpObserver]] = [:]
        var popupBackgroundReadyUntil: [ObjectIdentifier: ContinuousClock.Instant] = [:]
        let popupBackgroundClock = ContinuousClock()
        var popupBackgroundWarmCacheDuration = Duration.seconds(15)
        /// How long a popup request gives its extension's background content
        /// before presenting nothing at all.
        ///
        /// The product value answers to how long a click stays remembered. A test
        /// that has to see the presentation itself raises it, so a cold WebKit
        /// background on a loaded machine cannot cost it the popup.
        var popupBackgroundWarmUpDeadline = BrowserExtensionPopupBackgroundWarmUp.defaultDeadline
        /// WebKit normally calls its presentation delegate as soon as the
        /// popup document is ready. Bound that handoff so a missed callback
        /// cannot turn a remembered toolbar click into a permanent no-op.
        var popupPresentationDeadline = Duration.seconds(3)
    #endif
    var actionDidUpdate: (() -> Void)?
    private var isHostWindowFocused = true
    private var reportedFocusedWindow: BrowserExtensionWindowAdapter?

    init(
        webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry =
            BrowserExtensionWebpageMenuRegistry(),
        reportWindowFocus:
            @escaping (
                WKWebExtensionController,
                BrowserExtensionWindowAdapter?
            ) -> Void = { controller, window in
                controller.didFocusWindow(window)
            }
    ) {
        self.webpageMenuRegistry = webpageMenuRegistry
        self.reportWindowFocus = reportWindowFocus
        super.init()
        webpageMenuRegistry.userDidInvoke = { [weak self] client in
            self?.noteUserGesture(for: client)
        }
    }

    func connect<
        SessionHandler: BrowserExtensionTabWindowSessionHandling,
        PageProvider: BrowserExtensionPageProviding
    >(
        browser: SessionHandler,
        pageProvider: PageProvider,
        openCommandSettings:
            @escaping (
                BrowserExtensionCommandSettingsRoute,
                SpaceID
            ) -> Bool
    ) {
        self.browser = browser
        self.pageProvider = pageProvider
        self.openCommandSettings = openCommandSettings
        reconcile(session: browser.session)
    }

    func register(
        controller: WKWebExtensionController,
        spaceID: SpaceID
    ) {
        if let existing = controllers[spaceID] {
            precondition(
                existing.controller === controller,
                "A Space cannot replace its WebExtension controller at runtime."
            )
            return
        }
        let window = BrowserExtensionWindowAdapter(
            spaceID: spaceID,
            coordinator: self
        )
        controllers[spaceID] = BrowserExtensionControllerEntry(
            controller: controller,
            window: window
        )
        controller.delegate = self
        controller.didOpenWindow(window)
        if let state = currentState?.space(spaceID) {
            ensureAdapters(for: state)
            for tab in state.tabs {
                if let adapter = tabsBySpace[spaceID]?[tab.id] {
                    controller.didOpenTab(adapter)
                }
            }
        }
        reconcileWindowFocus()
    }

    func unregister(spaceID: SpaceID) {
        guard let entry = controllers[spaceID] else {
            return
        }
        if reportedFocusedWindow?.spaceID == spaceID {
            reportWindowFocus(entry.controller, nil)
            reportedFocusedWindow = nil
        }
        let auxiliaryWindows = auxiliaryWindowsBySpace[spaceID] ?? []
        for window in auxiliaryWindows {
            auxiliaryPresentations[ObjectIdentifier(window)]?.close()
        }
        auxiliaryWindowsBySpace.removeValue(forKey: spaceID)
        for window in auxiliaryWindows {
            auxiliaryPresentations.removeValue(
                forKey: ObjectIdentifier(window)
            )
        }
        auxiliaryWindowByTabID = auxiliaryWindowByTabID.filter {
            $0.value.spaceID != spaceID
        }
        controllers.removeValue(forKey: spaceID)
        if let adapters = tabsBySpace.removeValue(forKey: spaceID) {
            for adapter in adapters.values {
                entry.controller.didCloseTab(adapter, windowIsClosing: true)
            }
        }
        entry.controller.didCloseWindow(entry.window)
        entry.controller.delegate = nil
    }

    func reconcile(session: BrowserSession) {
        sidebarService?.repair(using: session)
        tabGroupService?.repair(using: session)
        // A closed tab must end its debugger session now, not at the next
        // command: the session holds a live Inspector connection to the page.
        debuggerService?.reconcileTargets()
        let newState = projectedState(for: session)
        let oldState = lastState

        for (spaceID, entry) in controllers {
            reconcile(
                controller: entry.controller,
                window: entry.window,
                spaceID: spaceID,
                previous: oldState?.space(spaceID),
                next: newState.space(spaceID)
            )
        }

        lastState = newState
        reconcileWindowFocus(selectedSpaceID: newState.selectedSpaceID)
    }

    /// Keeps WebKit's extension-window focus aligned with the real host window.
    /// A selected Space is not focused while Crest's browser window is not key.
    func setHostWindowFocused(_ isFocused: Bool) {
        guard isHostWindowFocused != isFocused else { return }
        isHostWindowFocused = isFocused
        reconcileWindowFocus()
    }

    private func reconcileWindowFocus(selectedSpaceID: SpaceID? = nil) {
        let selectedSpaceID = selectedSpaceID ?? currentState?.selectedSpaceID
        let desiredFocusedWindow: BrowserExtensionWindowAdapter?
        if isHostWindowFocused,
            let selectedSpaceID,
            let entry = controllers[selectedSpaceID]
        {
            desiredFocusedWindow = entry.window
        } else {
            desiredFocusedWindow = nil
        }

        reportFocusedWindow(desiredFocusedWindow)
    }

    private func reportFocusedWindow(
        _ desiredFocusedWindow: BrowserExtensionWindowAdapter?
    ) {
        guard reportedFocusedWindow !== desiredFocusedWindow else { return }

        if let reportedFocusedWindow,
            let entry = controllers[reportedFocusedWindow.spaceID]
        {
            reportWindowFocus(entry.controller, nil)
        }
        reportedFocusedWindow = nil

        if let desiredFocusedWindow,
            let entry = controllers[desiredFocusedWindow.spaceID]
        {
            reportWindowFocus(entry.controller, desiredFocusedWindow)
            reportedFocusedWindow = desiredFocusedWindow
        }
    }

    var currentState: BrowserExtensionSessionState? {
        browser.map { projectedState(for: $0.session) } ?? lastState
    }

    /// Projects a session together with the live page state extensions expect —
    /// load progress and reader mode — which the session value itself does not
    /// carry, plus any transient pages announced on top of it.
    private func projectedState(
        for session: BrowserSession
    ) -> BrowserExtensionSessionState {
        let projected = BrowserExtensionSessionState(
            session: session,
            runtimeActivity: { [weak self] spaceID, tabID in
                self?.runtimeActivity(for: tabID, in: spaceID) ?? .settled
            }
        )
        guard !transientTabsBySpace.isEmpty else { return projected }
        return BrowserExtensionSessionState(
            selectedSpaceID: projected.selectedSpaceID,
            spaces: projected.spaces.map { space in
                let transient = transientTabsBySpace[space.id] ?? []
                guard !transient.isEmpty else { return space }
                return BrowserExtensionSpaceState(
                    id: space.id,
                    tabs: space.tabs
                        + transientTabStates(
                            transient,
                            in: space.id,
                            startingAt: space.tabs.count
                        )
                )
            }
        )
    }

    /// The live page state for one tab, transient or not.
    ///
    /// A tab with no resident page reports settled rather than loading: an
    /// absent page has no navigation in flight to describe.
    private func runtimeActivity(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionTabRuntimeActivity {
        guard let pageProvider else { return .settled }
        return BrowserExtensionTabRuntimeActivity(
            isLoadingComplete: pageProvider.extensionWebView(
                for: tabID,
                in: spaceID
            )?.isLoading != true,
            isReaderModeActive: pageProvider.extensionReaderModeState(
                for: tabID,
                in: spaceID
            ).isActive
        )
    }

    /// Describes announced transient pages as tabs sitting after the Space's
    /// own, never selected: a Peek is a page the person is reading, not the
    /// Space's active tab, and reporting it as active would misdescribe both.
    private func transientTabStates(
        _ transient: [BrowserExtensionTransientTab],
        in spaceID: SpaceID,
        startingAt index: Int
    ) -> [BrowserExtensionTabState] {
        transient.enumerated().map { offset, tab in
            let webView = pageProvider?.extensionWebView(
                for: tab.id,
                in: spaceID
            )
            let activity = runtimeActivity(for: tab.id, in: spaceID)
            return BrowserExtensionTabState(
                id: tab.id,
                title: webView?.title ?? "",
                url: webView?.url ?? tab.url,
                placement: .current,
                index: index + offset,
                isSelected: false,
                isLoadingComplete: activity.isLoadingComplete,
                isReaderModeActive: activity.isReaderModeActive
            )
        }
    }

    func window(for spaceID: SpaceID) -> BrowserExtensionWindowAdapter? {
        controllers[spaceID]?.window
    }

    func window(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionWindowAdapter? {
        auxiliaryWindowByTabID[tabID] ?? controllers[spaceID]?.window
    }

    func tab(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionTabAdapter? {
        guard currentState?.space(spaceID)?.tab(tabID) != nil else { return nil }
        return adapter(for: tabID, in: spaceID)
    }
}

#if os(macOS)
    struct BrowserExtensionActionPopupRequest {
        let id: UUID
        let anchor: BrowserExtensionPopupAnchor?
    }
#endif

// MARK: - State

extension BrowserExtensionTabWindowCoordinator {

    func tabs(
        in window: BrowserExtensionWindowAdapter,
        context: WKWebExtensionContext
    ) -> [BrowserExtensionTabAdapter] {
        let spaceID = window.spaceID
        guard owns(context: context, spaceID: spaceID),
            let state = currentState?.space(spaceID)
        else {
            return []
        }
        ensureAdapters(for: state)
        return state.tabs.compactMap { tab in
            let assignedWindow =
                auxiliaryWindowByTabID[tab.id]
                ?? controllers[spaceID]?.window
            guard assignedWindow === window else { return nil }
            return tabsBySpace[spaceID]?[tab.id]
        }
    }

    func tabs(
        in spaceID: SpaceID,
        context: WKWebExtensionContext
    ) -> [BrowserExtensionTabAdapter] {
        guard let window = controllers[spaceID]?.window else { return [] }
        return tabs(in: window, context: context)
    }

    func activeTab(
        in window: BrowserExtensionWindowAdapter,
        context: WKWebExtensionContext
    ) -> BrowserExtensionTabAdapter? {
        let spaceID = window.spaceID
        guard owns(context: context, spaceID: spaceID)
        else {
            return nil
        }
        if window.isPrimary {
            guard
                let selectedID = currentState?.space(spaceID)?.selectedTabID,
                auxiliaryWindowByTabID[selectedID] == nil
            else {
                return nil
            }
            return adapter(for: selectedID, in: spaceID)
        }
        guard
            let tabID = auxiliaryWindowByTabID.first(where: {
                $0.value === window
            })?.key
        else {
            return nil
        }
        return adapter(for: tabID, in: spaceID)
    }

    func activeTab(
        in spaceID: SpaceID,
        context: WKWebExtensionContext
    ) -> BrowserExtensionTabAdapter? {
        guard let window = controllers[spaceID]?.window else { return nil }
        return activeTab(in: window, context: context)
    }

    func state(
        for tabID: TabID,
        in spaceID: SpaceID,
        context: WKWebExtensionContext
    ) -> BrowserExtensionTabState? {
        guard owns(context: context, spaceID: spaceID) else { return nil }
        guard let state = currentState?.space(spaceID)?.tab(tabID) else {
            return nil
        }
        guard auxiliaryWindowByTabID[tabID] != nil else { return state }
        return BrowserExtensionTabState(
            id: state.id,
            title: state.title,
            url: state.url,
            placement: state.placement,
            index: 0,
            isSelected: true,
            isLoadingComplete: state.isLoadingComplete,
            isReaderModeActive: state.isReaderModeActive
        )
    }

    func webView(
        for tabID: TabID,
        in spaceID: SpaceID,
        context: WKWebExtensionContext
    ) -> WKWebView? {
        guard owns(context: context, spaceID: spaceID) else { return nil }
        return pageProvider?.extensionWebView(for: tabID, in: spaceID)
    }

    func windowGeometry(
        for window: BrowserExtensionWindowAdapter
    ) -> BrowserExtensionWindowGeometry {
        if let presentation = auxiliaryPresentations[
            ObjectIdentifier(window)
        ] {
            return presentation.geometry
        }
        return pageProvider?.extensionWindowGeometry(in: window.spaceID)
            ?? .unavailable
    }

    func canRevealSensitiveProperties(
        of adapter: BrowserExtensionTabAdapter,
        state: BrowserExtensionTabState,
        context: WKWebExtensionContext
    ) -> Bool {
        // `tabs` is a context-wide permission. Asking WebKit whether it is
        // granted "in" this tab makes WebKit resolve the tab URL, which calls
        // this adapter again and can recurse until the process exhausts its
        // stack.
        if context.hasPermission(.tabs) {
            return true
        }
        if context.webExtension.requestedPermissions.contains(.activeTab),
            context.hasActiveUserGesture(in: adapter)
        {
            // WebKit records the gesture but does not include its temporary
            // activeTab grant in `hasAccess(to:in:)` on every supported OS.
            // Project the same grant into the adapter so action popups can read
            // the URL/title they were explicitly invoked for.
            return true
        }
        // A tab with no URL is Crest's Start Page. There is no host to match
        // against, so nothing but the `tabs` permission can justify handing its
        // title to an extension.
        guard let url = state.url else { return false }
        if url.scheme?.caseInsensitiveCompare(context.baseURL.scheme ?? "")
            == .orderedSame,
            url.host?.caseInsensitiveCompare(context.baseURL.host ?? "")
                == .orderedSame
        {
            // An extension always knows the URL of its own pages. Hiding that
            // URL prevents WebKit from associating the tab with the context and
            // makes the context's otherwise-private resources unavailable.
            return true
        }
        return context.hasAccess(to: url, in: adapter)
    }

    func reconcile(
        controller: WKWebExtensionController,
        window: BrowserExtensionWindowAdapter,
        spaceID: SpaceID,
        previous: BrowserExtensionSpaceState?,
        next: BrowserExtensionSpaceState?
    ) {
        let previousTabs = previous?.tabs ?? []
        let nextTabs = next?.tabs ?? []
        let previousByID = Dictionary(
            uniqueKeysWithValues: previousTabs.map { ($0.id, $0) }
        )
        let nextByID = Dictionary(
            uniqueKeysWithValues: nextTabs.map { ($0.id, $0) }
        )

        if let next {
            ensureAdapters(for: next)
        }

        for oldTab in previousTabs where nextByID[oldTab.id] == nil {
            if let adapter = tabsBySpace[spaceID]?[oldTab.id] {
                controller.didCloseTab(adapter)
                tabsBySpace[spaceID]?.removeValue(forKey: oldTab.id)
            }
        }
        for newTab in nextTabs where previousByID[newTab.id] == nil {
            if let adapter = tabsBySpace[spaceID]?[newTab.id] {
                controller.didOpenTab(adapter)
            }
        }
        for newTab in nextTabs {
            guard let oldTab = previousByID[newTab.id],
                let adapter = tabsBySpace[spaceID]?[newTab.id]
            else {
                continue
            }
            if oldTab.index != newTab.index {
                controller.didMoveTab(adapter, from: oldTab.index, in: window)
            }
            var changed: WKWebExtension.TabChangedProperties = []
            if oldTab.title != newTab.title { changed.insert(.title) }
            if oldTab.url != newTab.url { changed.insert(.URL) }
            if oldTab.placement != newTab.placement { changed.insert(.pinned) }
            if oldTab.isLoadingComplete != newTab.isLoadingComplete {
                changed.insert(.loading)
            }
            if oldTab.isReaderModeActive != newTab.isReaderModeActive {
                changed.insert(.readerMode)
            }
            if !changed.isEmpty {
                controller.didChangeTabProperties(changed, for: adapter)
            }
        }

        let oldSelected = previous?.selectedTabID
        let newSelected = next?.selectedTabID
        if oldSelected != newSelected {
            let oldAdapter = oldSelected.flatMap { tabsBySpace[spaceID]?[$0] }
            let newAdapter = newSelected.flatMap { tabsBySpace[spaceID]?[$0] }
            if let oldAdapter { controller.didDeselectTabs([oldAdapter]) }
            if let newAdapter {
                controller.didSelectTabs([newAdapter])
                controller.didActivateTab(
                    newAdapter,
                    previousActiveTab: oldAdapter
                )
            }
        }
    }

    func ensureAdapters(for state: BrowserExtensionSpaceState) {
        for tab in state.tabs where tabsBySpace[state.id]?[tab.id] == nil {
            tabsBySpace[state.id, default: [:]][tab.id] =
                BrowserExtensionTabAdapter(
                    tabID: tab.id,
                    spaceID: state.id,
                    coordinator: self
                )
        }
    }

    func adapter(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionTabAdapter? {
        if let existing = tabsBySpace[spaceID]?[tabID] {
            return existing
        }
        guard currentState?.space(spaceID)?.tab(tabID) != nil else { return nil }
        let adapter = BrowserExtensionTabAdapter(
            tabID: tabID,
            spaceID: spaceID,
            coordinator: self
        )
        tabsBySpace[spaceID, default: [:]][tabID] = adapter
        return adapter
    }

    func owns(
        context: WKWebExtensionContext,
        spaceID: SpaceID
    ) -> Bool {
        guard let controller = controllers[spaceID]?.controller else {
            return false
        }
        return context.webExtensionController === controller
    }

    func verifiedEntry(
        controller: WKWebExtensionController,
        context: WKWebExtensionContext
    ) -> BrowserExtensionControllerEntry? {
        verifiedSpaceAndEntry(controller: controller, context: context)?.1
    }

    func verifiedSpaceAndEntry(
        controller: WKWebExtensionController,
        context: WKWebExtensionContext
    ) -> (SpaceID, BrowserExtensionControllerEntry)? {
        guard context.webExtensionController === controller,
            let result = controllers.first(where: {
                $0.value.controller === controller
            })
        else {
            return nil
        }
        return result
    }

    func validates(
        _ window: (any WKWebExtensionWindow)?,
        for spaceID: SpaceID
    ) -> Bool {
        guard let window else { return true }
        guard let adapter = window as? BrowserExtensionWindowAdapter,
            adapter.spaceID == spaceID
        else {
            return false
        }
        return adapter === controllers[spaceID]?.window
            || auxiliaryWindowsBySpace[spaceID]?.contains(where: {
                $0 === adapter
            }) == true
    }

    func validates(
        _ tab: (any WKWebExtensionTab)?,
        for spaceID: SpaceID
    ) -> Bool {
        guard let tab else { return true }
        return (tab as? BrowserExtensionTabAdapter)?.spaceID == spaceID
    }

    func normalized(index: Int) -> Int? {
        index == NSNotFound ? nil : index
    }

    func adapterError(_ code: BrowserExtensionAdapterErrorCode) -> NSError {
        let description: String =
            switch code {
            case .tabUnavailable:
                "The requested tab is no longer available in this Space."
            case .windowUnavailable:
                "The requested Space window is unavailable."
            case .crossSpaceRequest:
                "Extensions cannot access tabs or windows from another Space."
            case .unsupportedOperation:
                "Crest does not support this window operation."
            case .optionsPageUnavailable:
                "This extension does not provide an options page."
            }
        return NSError(
            domain: "com.pauldavis.crest.web-extension-adapter",
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

// MARK: - Tab Operations

extension BrowserExtensionTabWindowCoordinator {
    func activate(
        tabID: TabID,
        spaceID: SpaceID,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if let window = auxiliaryWindowByTabID[tabID],
            let presentation = auxiliaryPresentations[
                ObjectIdentifier(window)
            ]
        {
            presentation.focus()
            completionHandler(nil)
            return
        }
        guard let browser,
            browser.activateExtensionTab(tabID, in: spaceID)
        else {
            completionHandler(adapterError(.tabUnavailable))
            return
        }
        let session = browser.session
        pageProvider?.select(session: session)
        reconcile(session: session)
        completionHandler(nil)
    }

    func close(
        tabID: TabID,
        spaceID: SpaceID,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if let window = auxiliaryWindowByTabID[tabID],
            let presentation = auxiliaryPresentations[
                ObjectIdentifier(window)
            ]
        {
            presentation.close()
            completionHandler(nil)
            return
        }
        guard let browser,
            browser.closeExtensionTab(tabID, in: spaceID)
        else {
            completionHandler(adapterError(.tabUnavailable))
            return
        }
        let session = browser.session
        pageProvider?.select(session: session)
        reconcile(session: session)
        completionHandler(nil)
    }

    func load(
        _ url: URL,
        tabID: TabID,
        spaceID: SpaceID,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if let route = BrowserExtensionCommandSettingsRoute(url: url),
            openCommandSettings?(route, spaceID) == true
        {
            completionHandler(nil)
            return
        }
        completeLoad(
            url,
            tabID: tabID,
            spaceID: spaceID,
            completionHandler: completionHandler
        )
    }

    func replaceExtensionPageNavigation(
        _ url: URL,
        tabID: TabID,
        spaceID: SpaceID
    ) -> Bool {
        var didLoad = false
        completeLoad(url, tabID: tabID, spaceID: spaceID) { error in
            didLoad = error == nil
        }
        return didLoad
    }

    private func completeLoad(
        _ url: URL,
        tabID: TabID,
        spaceID: SpaceID,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if auxiliaryWindowByTabID[tabID] != nil,
            let webView = pageProvider?.extensionWebView(
                for: tabID,
                in: spaceID
            )
        {
            webView.load(URLRequest(url: url))
            reconcileCurrentSession()
            completionHandler(nil)
            return
        }
        guard let browser,
            browser.loadExtensionURL(url, in: tabID, spaceID: spaceID)
        else {
            completionHandler(adapterError(.tabUnavailable))
            return
        }
        let session = browser.session
        pageProvider?.loadExtensionURL(
            url,
            for: tabID,
            in: spaceID,
            session: session
        )
        reconcile(session: session)
        completionHandler(nil)
    }

    func setPinned(
        _ pinned: Bool,
        tabID: TabID,
        spaceID: SpaceID,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let browser,
            browser.setExtensionTabPinned(
                pinned,
                tabID: tabID,
                in: spaceID
            )
        else {
            completionHandler(adapterError(.tabUnavailable))
            return
        }
        reconcile(session: browser.session)
        completionHandler(nil)
    }

    /// Opens an extension's options page inside the Space that owns its
    /// context. An options page already open in that Space is focused rather
    /// than duplicated, and a page that is really a Crest settings route is
    /// handed to settings instead of loaded as a tab.
    func presentOptionsPage(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard
            let (spaceID, _) = controllers.first(where: {
                $0.value.controller === context.webExtensionController
            })
        else {
            completionHandler(adapterError(.windowUnavailable))
            return
        }
        guard let url = context.optionsPageURL else {
            completionHandler(adapterError(.optionsPageUnavailable))
            return
        }
        if let route = BrowserExtensionCommandSettingsRoute(url: url),
            openCommandSettings?(route, spaceID) == true
        {
            completionHandler(nil)
            return
        }
        if let existing = currentState?.space(spaceID)?.tabs.first(where: {
            $0.url == url
        }) {
            activate(
                tabID: existing.id,
                spaceID: spaceID,
                completionHandler: completionHandler
            )
            return
        }
        openTab(
            url: url,
            spaceID: spaceID,
            pinned: false,
            index: nil,
            selected: true
        ) { _, error in
            completionHandler(error)
        }
    }

    func readerModeState(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserReaderModeState {
        pageProvider?.extensionReaderModeState(for: tabID, in: spaceID)
            ?? .unavailable
    }

    func setReaderModeActive(
        _ isActive: Bool,
        tabID: TabID,
        spaceID: SpaceID,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let pageProvider else {
            completionHandler(adapterError(.tabUnavailable))
            return
        }
        Task { [weak self] in
            do {
                try await pageProvider.setExtensionReaderModeActive(
                    isActive,
                    for: tabID,
                    in: spaceID
                )
                if let session = self?.browser?.session {
                    self?.reconcile(session: session)
                }
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    func duplicate(
        tabID: TabID,
        spaceID: SpaceID,
        configuration: WKWebExtension.TabConfiguration,
        completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void
    ) {
        guard validates(configuration.window, for: spaceID) else {
            completionHandler(nil, adapterError(.crossSpaceRequest))
            return
        }
        guard let browser,
            let duplicateID = browser.duplicateExtensionTab(
                tabID,
                in: spaceID,
                pinned: configuration.shouldBePinned,
                requestedIndex: normalized(index: configuration.index),
                shouldSelect: configuration.shouldBeActive
            )
        else {
            completionHandler(nil, adapterError(.tabUnavailable))
            return
        }
        let session = browser.session
        if configuration.shouldBeActive {
            pageProvider?.select(session: session)
        }
        reconcile(session: session)
        completionHandler(adapter(for: duplicateID, in: spaceID), nil)
    }

    func focus(
        spaceID: SpaceID,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let browser,
            browser.session.space(id: spaceID) != nil
        else {
            completionHandler(adapterError(.windowUnavailable))
            return
        }
        browser.selectSpace(spaceID)
        let session = browser.session
        pageProvider?.select(session: session)
        reconcile(session: session)
        completionHandler(nil)
    }

    func focus(
        window: BrowserExtensionWindowAdapter,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if window.isPrimary {
            focus(
                spaceID: window.spaceID,
                completionHandler: completionHandler
            )
            return
        }
        guard
            let presentation = auxiliaryPresentations[
                ObjectIdentifier(window)
            ]
        else {
            completionHandler(adapterError(.windowUnavailable))
            return
        }
        presentation.focus()
        completionHandler(nil)
    }

    func close(
        window: BrowserExtensionWindowAdapter,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard !window.isPrimary,
            let presentation = auxiliaryPresentations[
                ObjectIdentifier(window)
            ]
        else {
            completionHandler(adapterError(.unsupportedOperation))
            return
        }
        presentation.close()
        completionHandler(nil)
    }

    func openTab(
        url: URL?,
        spaceID: SpaceID,
        pinned: Bool,
        index: Int?,
        selected: Bool,
        completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void
    ) {
        guard let browser,
            let tabID = browser.openExtensionTab(
                url: url,
                in: spaceID,
                pinned: pinned,
                requestedIndex: index,
                shouldSelect: selected
            )
        else {
            completionHandler(nil, adapterError(.tabUnavailable))
            return
        }
        let session = browser.session
        // Give WebKit the selected tab's web view before reporting the tab, then
        // begin its navigation only after that report. Extension resources and
        // runtime APIs are served through this exact three-phase association.
        if selected {
            pageProvider?.prepareExtensionSelection(session: session)
        }
        reconcile(session: session)
        let openedTab = adapter(for: tabID, in: spaceID)
        completionHandler(openedTab, nil)
        if selected {
            pageProvider?.select(session: browser.session)
        }
    }
}

// MARK: - Transient Tabs

extension BrowserExtensionTabWindowCoordinator {

    /// Announces a page the session does not carry, so extensions can answer
    /// the content scripts WebKit is about to run inside it.
    ///
    /// Register before the page begins its first navigation. WebKit injects a
    /// document-start content script during that load and resolves the messages
    /// it sends by mapping its web view onto an announced tab; a script that
    /// asks its background for configuration before the announcement is
    /// rejected outright rather than queued, and nothing retries it for the life
    /// of that document.
    func registerTransientTab(
        _ tab: BrowserExtensionTransientTab,
        in spaceID: SpaceID
    ) {
        if let pendingAuxiliaryWindow,
            pendingAuxiliaryWindow.spaceID == spaceID
        {
            auxiliaryWindowByTabID[tab.id] = pendingAuxiliaryWindow
        }
        var transient = transientTabsBySpace[spaceID] ?? []
        if let existing = transient.firstIndex(where: { $0.id == tab.id }) {
            transient[existing] = tab
        } else {
            transient.append(tab)
        }
        transientTabsBySpace[spaceID] = transient
        reconcileCurrentSession()
    }

    /// Withdraws a transient page, closing the tab extensions were told about.
    ///
    /// The page is gone either way — released, evicted under memory pressure, or
    /// handed to a real tab that announces itself — so leaving the announcement
    /// standing would be the dishonest outcome.
    func unregisterTransientTab(_ tabID: TabID, in spaceID: SpaceID) {
        guard var transient = transientTabsBySpace[spaceID],
            transient.contains(where: { $0.id == tabID })
        else { return }
        transient.removeAll { $0.id == tabID }
        if transient.isEmpty {
            transientTabsBySpace.removeValue(forKey: spaceID)
        } else {
            transientTabsBySpace[spaceID] = transient
        }
        reconcileCurrentSession()
    }

    /// Re-runs the diff against the session already in hand.
    ///
    /// Transient pages appear and disappear without the session changing at all,
    /// so they have no store update to ride in on.
    func reconcileCurrentSession() {
        guard let browser else { return }
        reconcile(session: browser.session)
    }
}

// MARK: - Auxiliary Windows

extension BrowserExtensionTabWindowCoordinator {
    func openAuxiliaryWindow(
        _ request: BrowserExtensionWindowPresentationRequest,
        in spaceID: SpaceID,
        announceToController: Bool = false,
        completionHandler:
            @escaping ((any WKWebExtensionWindow)?, Error?) -> Void
    ) {
        guard let browser,
            let space = browser.session.space(id: spaceID),
            let pageProvider,
            let extensionController = controllers[spaceID]?.controller
        else {
            completionHandler(nil, adapterError(.windowUnavailable))
            return
        }

        let window = BrowserExtensionWindowAdapter(
            spaceID: spaceID,
            windowType: request.windowType,
            isPrimary: false,
            coordinator: self
        )
        auxiliaryWindowsBySpace[spaceID, default: []].append(window)
        if announceToController {
            // A brokered fallback did not originate in WebKit's
            // `openNewWindowUsing` delegate, so WebKit can assign the new
            // window and tab their native API identities only after the host
            // explicitly announces the window. Announce it before the page
            // provider registers its transient tab.
            extensionController.didOpenWindow(window)
        }
        pendingAuxiliaryWindow = window
        let presentation = pageProvider.presentExtensionWindow(
            request,
            in: space,
            didFocus: { [weak self, weak window] tabID in
                guard let self, let window,
                    self.auxiliaryWindowByTabID[tabID] === window
                else { return }
                self.reportFocusedWindow(window)
            },
            didClose: { [weak self] tabID in
                self?.auxiliaryWindowDidClose(tabID: tabID)
            }
        )
        pendingAuxiliaryWindow = nil

        guard let presentation,
            auxiliaryWindowByTabID[presentation.extensionTabID] === window
        else {
            auxiliaryWindowsBySpace[spaceID]?.removeAll { $0 === window }
            if announceToController {
                extensionController.didCloseWindow(window)
            }
            completionHandler(nil, adapterError(.windowUnavailable))
            return
        }
        auxiliaryPresentations[ObjectIdentifier(window)] = presentation
        completionHandler(window, nil)
        if request.shouldFocus {
            reportFocusedWindow(window)
        }
    }

    private func auxiliaryWindowDidClose(tabID: TabID) {
        guard let window = auxiliaryWindowByTabID.removeValue(forKey: tabID)
        else { return }
        auxiliaryPresentations.removeValue(forKey: ObjectIdentifier(window))
        auxiliaryWindowsBySpace[window.spaceID]?.removeAll {
            $0 === window
        }
        if auxiliaryWindowsBySpace[window.spaceID]?.isEmpty == true {
            auxiliaryWindowsBySpace.removeValue(forKey: window.spaceID)
        }
        if reportedFocusedWindow === window {
            reportFocusedWindow(nil)
            reconcileWindowFocus()
        }
        controllers[window.spaceID]?.controller.didCloseWindow(window)
    }
}

// MARK: - WebExtension Delegate Operations

extension BrowserExtensionTabWindowCoordinator {
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        guard
            let entry = verifiedEntry(
                controller: controller,
                context: extensionContext
            )
        else {
            return []
        }
        let auxiliary = auxiliaryWindowsBySpace[entry.window.spaceID] ?? []
        if let reportedFocusedWindow,
            reportedFocusedWindow.spaceID == entry.window.spaceID,
            !reportedFocusedWindow.isPrimary
        {
            return [reportedFocusedWindow, entry.window]
                + auxiliary.filter { $0 !== reportedFocusedWindow }
        }
        return [entry.window] + auxiliary
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard
            let (spaceID, _) = verifiedSpaceAndEntry(
                controller: controller,
                context: extensionContext
            ), let reportedFocusedWindow,
            reportedFocusedWindow.spaceID == spaceID
        else {
            return nil
        }
        return reportedFocusedWindow
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void
    ) {
        guard
            let (spaceID, _) = verifiedSpaceAndEntry(
                controller: controller,
                context: extensionContext
            ), validates(configuration.window, for: spaceID),
            validates(configuration.parentTab, for: spaceID)
        else {
            completionHandler(nil, adapterError(.crossSpaceRequest))
            return
        }
        if let url = configuration.url,
            let route = BrowserExtensionCommandSettingsRoute(url: url),
            openCommandSettings?(route, spaceID) == true
        {
            completionHandler(nil, nil)
            return
        }
        openTab(
            url: configuration.url,
            spaceID: spaceID,
            pinned: configuration.shouldBePinned,
            index: normalized(index: configuration.index),
            selected: configuration.shouldBeActive,
            completionHandler: completionHandler
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext context: WKWebExtensionContext
    ) {
        guard
            verifiedEntry(
                controller: controller,
                context: context
            ) != nil
        else { return }
        actionDidUpdate?()
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, Error?) -> Void
    ) {
        guard
            let (spaceID, entry) = verifiedSpaceAndEntry(
                controller: controller,
                context: extensionContext
            ), !configuration.shouldBePrivate,
            configuration.tabs.allSatisfy({ validates($0, for: spaceID) })
        else {
            completionHandler(nil, adapterError(.crossSpaceRequest))
            return
        }

        if configuration.windowType == .popup,
            configuration.tabs.isEmpty,
            configuration.tabURLs.count == 1,
            let url = configuration.tabURLs.first
        {
            openAuxiliaryWindow(
                BrowserExtensionWindowPresentationRequest(
                    url: url,
                    title: extensionContext.webExtension.displayName
                        ?? "Extension",
                    frame: configuration.frame,
                    windowType: configuration.windowType,
                    windowState: configuration.windowState,
                    shouldFocus: configuration.shouldBeFocused
                ),
                in: spaceID,
                completionHandler: completionHandler
            )
            return
        }

        for existingTab in configuration.tabs {
            guard let adapter = existingTab as? BrowserExtensionTabAdapter else {
                continue
            }
            if configuration.shouldBeFocused {
                _ = browser?.activateExtensionTab(adapter.tabID, in: spaceID)
            }
        }
        let urls = configuration.tabURLs
        if urls.isEmpty, configuration.tabs.isEmpty {
            _ = browser?.openExtensionTab(
                url: nil,
                in: spaceID,
                pinned: false,
                requestedIndex: nil,
                shouldSelect: configuration.shouldBeFocused
            )
        } else {
            for (index, url) in urls.enumerated() {
                _ = browser?.openExtensionTab(
                    url: url,
                    in: spaceID,
                    pinned: false,
                    requestedIndex: nil,
                    shouldSelect: configuration.shouldBeFocused
                        && index == urls.index(before: urls.endIndex)
                )
            }
        }
        if let browser {
            let session = browser.session
            if configuration.shouldBeFocused {
                pageProvider?.prepareExtensionSelection(session: session)
            }
            reconcile(session: session)
            completionHandler(entry.window, nil)
            if configuration.shouldBeFocused {
                pageProvider?.select(session: browser.session)
            }
            return
        }
        completionHandler(entry.window, nil)
    }
}
