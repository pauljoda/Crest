import Foundation
import WebKit

struct BrowserExtensionControllerEntry {
    let controller: WKWebExtensionController
    let window: BrowserExtensionWindowAdapter
}

@MainActor
final class BrowserExtensionTabWindowCoordinator: NSObject {

    private let reportWindowFocus: (WKWebExtensionController, BrowserExtensionWindowAdapter?) -> Void
    let permissionPrompts = BrowserExtensionPermissionPromptController()
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
    var hostWindows: [BrowserWindowID: BrowserExtensionHostWindow] = [:]
    var hostWindowOrder: [BrowserWindowID] = []
    var windowsBySpace: [SpaceID: [BrowserWindowID: BrowserExtensionWindowAdapter]] = [:]
    var tabOwnerWindowIDs: [TabID: BrowserWindowID] = [:]
    var focusedHostWindowID: BrowserWindowID?
    var hasRegisteredHostWindows = false
    var lastSelectedTabsByWindow: [ObjectIdentifier: TabID] = [:]
    var lastWindowsByTabID: [TabID: BrowserExtensionWindowAdapter] = [:]
    var tabGroupWindowDescriptors: [BrowserExtensionTabGroupID: [String: Any]] = [:]
    var openCommandSettings: ((BrowserExtensionCommandSettingsRoute, SpaceID) -> Bool)?
    var nativeMessagingHandler: BrowserExtensionNativeMessagingHandling?
    var sidebarService: (any BrowserExtensionSidebarHandling)?
    var tabGroupService: (any BrowserExtensionTabGroupHandling)?
    /// Holds the `modifyHeaders` request-header operations WebKit refuses, so
    /// every context of one extension applies the same table.
    var declarativeNetRequestService: (any BrowserExtensionDeclarativeNetRequestHandling)?
    /// Carries `runtime.onMessageExternal` deliveries WebKit cannot route,
    /// which is every one sent from a frame inside a Crest-hosted extension
    /// document. Owned here rather than injected: it is pure routing state
    /// with no platform behind it, and the coordinator is the only writer.
    let externalMessageRegistry = BrowserExtensionExternalMessageRegistry()
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
    /// Runs `identity.launchWebAuthFlow` in a Crest-owned web view. Supplied
    /// by the platform shell; absent means every flow is refused, because a
    /// pool assembled for a test or a preview has no window to present one in.
    var webAuthFlowHost: (any BrowserExtensionWebAuthFlowHosting)?
    /// The extension contexts currently running an authorization flow. One at
    /// a time per extension: see `handleCapabilityBrokerIdentity`.
    var webAuthFlowsInFlight: Set<ObjectIdentifier> = []
    var verifiedNativeMessagingIdentities: [ObjectIdentifier: BrowserExtensionNativeMessagingIdentity] = [:]
    var verifiedNativeMessagingAuthorizations: [ObjectIdentifier: BrowserExtensionNativeMessagingAuthorization] = [:]
    #if os(macOS)
        var pendingActionPopupRequests: [ObjectIdentifier: BrowserExtensionActionPopupRequest] = [:]
        var pendingToolbarActionContexts: Set<ObjectIdentifier> = []
        let popupToggle = BrowserExtensionPopupToggle()
        var backgroundHealthContexts: Set<ObjectIdentifier> = []
        var popupBackgroundRecoveryRequests: Set<ObjectIdentifier> = []
        var popupBackgroundPreparations: [ObjectIdentifier: BrowserExtensionPopupBackgroundPreparation] = [:]
        var popupBackgroundReadyEndpoints: [ObjectIdentifier: UUID] = [:]
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
    var reportedFocusedWindow: BrowserExtensionWindowAdapter?

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
            hostWindowID: preferredHost(in: spaceID)?.id,
            coordinator: self
        )
        controllers[spaceID] = BrowserExtensionControllerEntry(
            controller: controller,
            window: window
        )
        controller.delegate = self
        controller.didOpenWindow(window)
        registerHostAdapters(in: spaceID)
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
        let hostAdapters = windowsBySpace.removeValue(forKey: spaceID)?.values.map { $0 } ?? []
        for window in hostAdapters where window !== entry.window { entry.controller.didCloseWindow(window) }
        entry.controller.didCloseWindow(entry.window)
        entry.controller.delegate = nil
    }

    func reconcile(session: BrowserSession) {
        let session = combinedSession(fallback: session)
        reconcileTabOwners()
        sidebarService?.repair(using: session)
        if hostWindows.isEmpty { tabGroupService?.repair(using: session) }
        // A closed tab must end its debugger session now, not at the next
        // command: the session holds a live Inspector connection to the page.
        debuggerService?.reconcileTargets()
        let projection = projectedState(for: session)
        let newState = projection.state
        let oldState = lastState
        for space in session.spaces {
            for group in tabGroupService?.groups(in: space.id) ?? [] {
                if let descriptor = brokerWindowDescriptor(group.tabs.first.flatMap { window(for: $0, in: space.id) }) {
                    tabGroupWindowDescriptors[group.id] = descriptor
                }
            }
        }

        for (spaceID, entry) in controllers {
            reconcile(
                controller: entry.controller,
                window: entry.window,
                spaceID: spaceID,
                previous: oldState?.space(spaceID),
                next: newState.space(spaceID),
                windowsByTabID: projection.windowsByTabID
            )
        }

        lastState = newState
        lastWindowsByTabID = projection.windowsByTabID
        reconcileWindowFocus(selectedSpaceID: newState.selectedSpaceID)
        permissionPrompts.reconcile()
    }

    /// Keeps WebKit's extension-window focus aligned with the real host window.
    /// A selected Space is not focused while Crest's browser window is not key.
    func setHostWindowFocused(_ isFocused: Bool) {
        guard isHostWindowFocused != isFocused else { return }
        isHostWindowFocused = isFocused
        reconcileWindowFocus()
    }

    func reconcileWindowFocus(selectedSpaceID: SpaceID? = nil) {
        if !hostWindows.isEmpty {
            let host = focusedHostWindowID.flatMap { hostWindows[$0] }
            let window = host.flatMap { host in
                host.browser.flatMap { windowsBySpace[$0.session.selectedSpaceID]?[host.id] }
            }
            reportFocusedWindow(window)
            return
        }
        let selectedSpaceID = selectedSpaceID ?? browser?.session.selectedSpaceID ?? lastState?.selectedSpaceID
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

    func reportFocusedWindow(
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
        if let session = browser?.session ?? hostWindowOrder.compactMap({ hostWindows[$0]?.browser?.session }).first {
            return projectedState(for: combinedSession(fallback: session)).state
        }
        return lastState
    }

    /// Reads only the requested tab's live activity. Native metadata getters
    /// run once per property, so projecting every Space here would repeatedly
    /// resolve unrelated pages while WebKit enumerates the tabs in one window.
    private func projectedTabState(
        for tabID: TabID,
        in spaceID: SpaceID,
        includingWindowIndex: Bool = true
    ) -> BrowserExtensionTabState? {
        guard let browser = browser(for: tabID, in: spaceID) else {
            return self.browser == nil && hostWindows.isEmpty ? lastState?.space(spaceID)?.tab(tabID) : nil
        }
        guard let space = browser.session.space(id: spaceID) else { return nil }
        if let index = space.tabs.firstIndex(where: { $0.id == tabID }) {
            return BrowserExtensionTabState(
                tab: space.tabs[index],
                index: hostWindows.isEmpty || !includingWindowIndex
                    ? index : ownedTabIDs(in: window(for: tabID, in: spaceID)).firstIndex(of: tabID) ?? index,
                isSelected: tabID == space.selectedTabID,
                runtimeActivity: runtimeActivity(for: tabID, in: spaceID)
            )
        }
        guard let transient = transientTabsBySpace[spaceID],
            let offset = transient.firstIndex(where: { $0.id == tabID })
        else { return nil }
        return transientTabState(
            transient[offset],
            in: spaceID,
            at: space.tabs.count + offset
        )
    }

    /// Projects a session together with the live page state extensions expect —
    /// load progress and reader mode — which the session value itself does not
    /// carry, plus any transient pages announced on top of it.
    private func projectedState(
        for session: BrowserSession
    ) -> (state: BrowserExtensionSessionState, windowsByTabID: [TabID: BrowserExtensionWindowAdapter]) {
        let projected: BrowserExtensionSessionState
        var windowsByTabID: [TabID: BrowserExtensionWindowAdapter]
        if hostWindows.isEmpty {
            projected = BrowserExtensionSessionState(
                session: session,
                runtimeActivity: { [weak self] spaceID, tabID in
                    self?.runtimeActivity(for: tabID, in: spaceID) ?? .settled
                }
            )
            windowsByTabID = Dictionary(
                uniqueKeysWithValues: projected.spaces.flatMap { space in
                    space.tabs.compactMap { tab in window(for: tab.id, in: space.id).map { (tab.id, $0) } }
                })
        } else {
            let projection = projectedHostState(for: session)
            projected = projection.state
            windowsByTabID = projection.windowsByTabID
        }
        guard !transientTabsBySpace.isEmpty else { return (projected, windowsByTabID) }
        for space in projected.spaces {
            for tab in transientTabsBySpace[space.id] ?? [] {
                windowsByTabID[tab.id] = window(for: tab.id, in: space.id)
            }
        }
        let state = BrowserExtensionSessionState(
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
        return (state, windowsByTabID)
    }

    /// The live page state for one tab, transient or not.
    ///
    /// A tab with no resident page reports settled rather than loading: an
    /// absent page has no navigation in flight to describe.
    private func runtimeActivity(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionTabRuntimeActivity {
        guard let pageProvider = pageProvider(for: tabID, in: spaceID) else { return .settled }
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
            transientTabState(tab, in: spaceID, at: index + offset)
        }
    }

    private func transientTabState(
        _ tab: BrowserExtensionTransientTab,
        in spaceID: SpaceID,
        at index: Int
    ) -> BrowserExtensionTabState {
        let webView = pageProvider(for: tab.id, in: spaceID)?.extensionWebView(for: tab.id, in: spaceID)
        let activity = runtimeActivity(for: tab.id, in: spaceID)
        return BrowserExtensionTabState(
            id: tab.id,
            title: webView?.title ?? "",
            url: webView?.url ?? tab.url,
            placement: .current,
            index: index,
            isSelected: false,
            isLoadingComplete: activity.isLoadingComplete,
            isReaderModeActive: activity.isReaderModeActive
        )
    }

    func window(for spaceID: SpaceID) -> BrowserExtensionWindowAdapter? {
        preferredHost(in: spaceID).flatMap { windowsBySpace[spaceID]?[$0.id] } ?? controllers[spaceID]?.window
    }

    func window(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionWindowAdapter? {
        auxiliaryWindowByTabID[tabID]
            ?? ownerHost(for: tabID, in: spaceID).flatMap { windowsBySpace[spaceID]?[$0.id] }
            ?? controllers[spaceID]?.window
    }

    func tab(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionTabAdapter? {
        guard projectedTabState(for: tabID, in: spaceID) != nil else { return nil }
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
        guard owns(context: context, spaceID: spaceID) else { return [] }
        let ids = ownedTabIDs(in: window)
        return ids.compactMap { tabID in
            let assignedWindow = self.window(for: tabID, in: spaceID)
            guard assignedWindow === window else { return nil }
            return registeredAdapter(for: tabID, in: spaceID)
        }
    }

    func selectedTabID(in spaceID: SpaceID) -> TabID? {
        guard let browser = preferredHost(in: spaceID)?.browser ?? browser else {
            return lastState?.space(spaceID)?.selectedTabID
        }
        guard let space = browser.session.space(id: spaceID), let id = space.selectedTabID,
            space.tabs.contains(where: { $0.id == id })
        else { return nil }
        return id
    }

    func tabs(
        in spaceID: SpaceID,
        context: WKWebExtensionContext
    ) -> [BrowserExtensionTabAdapter] {
        guard let window = window(for: spaceID) else { return [] }
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
            let selected: TabID?
            if let host = host(for: window) {
                selected = host.browser?.session.space(id: spaceID)?.selectedTabID
            } else {
                selected = selectedTabID(in: spaceID)
            }
            guard
                let selectedID = selected,
                self.window(for: selectedID, in: spaceID) === window
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
        guard let window = window(for: spaceID) else { return nil }
        return activeTab(in: window, context: context)
    }

    func state(
        for tabID: TabID,
        in spaceID: SpaceID,
        context: WKWebExtensionContext,
        includingWindowIndex: Bool = true
    ) -> BrowserExtensionTabState? {
        guard owns(context: context, spaceID: spaceID) else { return nil }
        guard let state = projectedTabState(for: tabID, in: spaceID, includingWindowIndex: includingWindowIndex) else {
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
        return pageProvider(for: tabID, in: spaceID)?.extensionWebView(for: tabID, in: spaceID)
    }

    func windowGeometry(
        for window: BrowserExtensionWindowAdapter
    ) -> BrowserExtensionWindowGeometry {
        if let presentation = auxiliaryPresentations[
            ObjectIdentifier(window)
        ] {
            return presentation.geometry
        }
        if let host = host(for: window) {
            return host.pageProvider?.extensionWindowGeometry(in: window.spaceID) ?? .unavailable
        }
        guard !hasRegisteredHostWindows else { return .unavailable }
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
        next: BrowserExtensionSpaceState?,
        windowsByTabID: [TabID: BrowserExtensionWindowAdapter]
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
            let currentWindow = windowsByTabID[newTab.id] ?? window
            let previousWindow = lastWindowsByTabID[newTab.id] ?? currentWindow
            if oldTab.index != newTab.index || previousWindow !== currentWindow {
                controller.didMoveTab(adapter, from: oldTab.index, in: previousWindow)
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

        if !hostWindows.isEmpty {
            reconcileHostSelections(in: spaceID, controller: controller)
            return
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
        for tab in state.tabs { _ = registeredAdapter(for: tab.id, in: state.id) }
    }

    func adapter(for tabID: TabID, in spaceID: SpaceID) -> BrowserExtensionTabAdapter? {
        if let existing = tabsBySpace[spaceID]?[tabID] { return existing }
        guard projectedTabState(for: tabID, in: spaceID) != nil else { return nil }
        return registeredAdapter(for: tabID, in: spaceID)
    }

    /// Callers establish live or detached-snapshot membership before registering.
    /// Enumerating identities must not read loading/reader state for every page.
    private func registeredAdapter(for tabID: TabID, in spaceID: SpaceID) -> BrowserExtensionTabAdapter {
        if let existing = tabsBySpace[spaceID]?[tabID] { return existing }
        let adapter = BrowserExtensionTabAdapter(tabID: tabID, spaceID: spaceID, coordinator: self)
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
            || windowsBySpace[spaceID]?.values.contains(where: { $0 === adapter }) == true
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
        guard let browser = browser(for: tabID, in: spaceID),
            browser.activateExtensionTab(tabID, in: spaceID)
        else {
            completionHandler(adapterError(.tabUnavailable))
            return
        }
        let session = browser.session
        ownerHost(for: tabID, in: spaceID)?.focus()
        pageProvider(for: tabID, in: spaceID)?.select(session: session)
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
        let pageProvider = pageProvider(for: tabID, in: spaceID)
        guard let browser = browser(for: tabID, in: spaceID),
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
            let webView = pageProvider(for: tabID, in: spaceID)?.extensionWebView(
                for: tabID,
                in: spaceID
            )
        {
            webView.load(URLRequest(url: url))
            reconcileCurrentSession()
            completionHandler(nil)
            return
        }
        guard let browser = browser(for: tabID, in: spaceID),
            browser.loadExtensionURL(url, in: tabID, spaceID: spaceID)
        else {
            completionHandler(adapterError(.tabUnavailable))
            return
        }
        let session = browser.session
        pageProvider(for: tabID, in: spaceID)?.loadExtensionURL(
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
        guard let browser = browser(for: tabID, in: spaceID),
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
        pageProvider(for: tabID, in: spaceID)?.extensionReaderModeState(for: tabID, in: spaceID)
            ?? .unavailable
    }

    func setReaderModeActive(
        _ isActive: Bool,
        tabID: TabID,
        spaceID: SpaceID,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let pageProvider = pageProvider(for: tabID, in: spaceID) else {
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
                if let session = self?.browser(for: tabID, in: spaceID)?.session {
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
        let destination =
            host(for: configuration.window as? BrowserExtensionWindowAdapter) ?? ownerHost(for: tabID, in: spaceID)
        let destinationWindow = destination.flatMap { windowsBySpace[spaceID]?[$0.id] }
        guard let browser = destination?.browser ?? browser(for: tabID, in: spaceID),
            let duplicateID = browser.duplicateExtensionTab(
                tabID,
                in: spaceID,
                pinned: configuration.shouldBePinned,
                requestedIndex: normalized(index: configuration.index).map {
                    sessionInsertionIndex($0, in: destinationWindow)
                },
                shouldSelect: configuration.shouldBeActive
            )
        else {
            completionHandler(nil, adapterError(.tabUnavailable))
            return
        }
        let session = browser.session
        if let destination { tabOwnerWindowIDs[duplicateID] = destination.id }
        if configuration.shouldBeActive {
            (destination?.pageProvider ?? pageProvider(for: tabID, in: spaceID))?.select(session: session)
        }
        reconcile(session: session)
        completionHandler(adapter(for: duplicateID, in: spaceID), nil)
    }

    func focus(
        spaceID: SpaceID,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let browser = preferredHost(in: spaceID)?.browser ?? browser,
            browser.session.space(id: spaceID) != nil
        else {
            completionHandler(adapterError(.windowUnavailable))
            return
        }
        browser.selectSpace(spaceID)
        let session = browser.session
        preferredHost(in: spaceID)?.focus()
        (preferredHost(in: spaceID)?.pageProvider ?? pageProvider)?.select(session: session)
        reconcile(session: session)
        completionHandler(nil)
    }

    func focus(
        window: BrowserExtensionWindowAdapter,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if let host = host(for: window), let browser = host.browser {
            browser.selectSpace(window.spaceID)
            host.focus()
            host.pageProvider?.select(session: browser.session)
            reconcile(session: browser.session)
            completionHandler(nil)
            return
        }
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
        if let host = host(for: window) {
            host.close()
            completionHandler(nil)
            return
        }
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
        window: BrowserExtensionWindowAdapter? = nil,
        completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void
    ) {
        let url = BrowserExtensionNewTabURL.resolve(url)
        let host = host(for: window) ?? preferredHost(in: spaceID)
        let destinationWindow = window ?? host.flatMap { windowsBySpace[spaceID]?[$0.id] }
        let pageProvider = host?.pageProvider ?? pageProvider
        guard let browser = host?.browser ?? browser,
            let tabID = browser.openExtensionTab(
                url: url,
                in: spaceID,
                pinned: pinned,
                requestedIndex: index.map { sessionInsertionIndex($0, in: destinationWindow) },
                shouldSelect: selected
            )
        else {
            completionHandler(nil, adapterError(.tabUnavailable))
            return
        }
        if let host { tabOwnerWindowIDs[tabID] = host.id }
        let session = browser.session
        // Prepare every requested tab before reporting it, then navigate after
        // the announcement. Inactive extension tabs also run immediately: an
        // extension may use one for migration or other background page work.
        if selected {
            pageProvider?.prepareExtensionSelection(session: session)
        } else {
            pageProvider?.prepareExtensionTab(for: tabID, in: spaceID, session: session)
        }
        reconcile(session: session)
        let openedTab = adapter(for: tabID, in: spaceID)
        completionHandler(openedTab, nil)
        if selected {
            pageProvider?.select(session: browser.session)
        } else if let url {
            pageProvider?.loadExtensionURL(url, for: tabID, in: spaceID, session: browser.session)
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
        in spaceID: SpaceID,
        windowID: BrowserWindowID? = nil
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
        if let windowID { tabOwnerWindowIDs[tab.id] = windowID }
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
        guard let browser = browser ?? hostWindowOrder.compactMap({ hostWindows[$0]?.browser }).first else { return }
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
        guard let browser = preferredHost(in: spaceID)?.browser ?? browser,
            let space = browser.session.space(id: spaceID),
            let pageProvider = preferredHost(in: spaceID)?.pageProvider ?? pageProvider,
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
        let spaceID = entry.window.spaceID
        let primary = hostWindowOrder.compactMap { windowsBySpace[spaceID]?[$0] }
        let windows =
            (primary.isEmpty ? [entry.window] : primary)
            + (auxiliaryWindowsBySpace[spaceID] ?? [])
        if let reportedFocusedWindow,
            reportedFocusedWindow.spaceID == spaceID
        {
            return [reportedFocusedWindow] + windows.filter { $0 !== reportedFocusedWindow }
        }
        return windows
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
            window: configuration.window as? BrowserExtensionWindowAdapter,
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

        let host = preferredHost(in: spaceID)
        let browser = host?.browser ?? browser
        let pageProvider = host?.pageProvider ?? pageProvider

        for existingTab in configuration.tabs {
            guard let adapter = existingTab as? BrowserExtensionTabAdapter else {
                continue
            }
            if configuration.shouldBeFocused {
                _ = browser?.activateExtensionTab(adapter.tabID, in: spaceID)
            }
        }
        let urls = configuration.tabURLs.map(BrowserExtensionNewTabURL.resolve)
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
            completionHandler(window(for: spaceID) ?? entry.window, nil)
            if configuration.shouldBeFocused {
                pageProvider?.select(session: browser.session)
            }
            return
        }
        completionHandler(window(for: spaceID) ?? entry.window, nil)
    }
}
