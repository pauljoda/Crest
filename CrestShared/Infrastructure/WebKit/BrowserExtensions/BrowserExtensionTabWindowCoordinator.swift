import Foundation
import WebKit

@MainActor
final class BrowserExtensionTabWindowCoordinator: NSObject {

    var controllers: [SpaceID: BrowserExtensionControllerEntry] = [:]
    var tabsBySpace: [SpaceID: [TabID: BrowserExtensionTabAdapter]] = [:]
    var transientTabsBySpace: [SpaceID: [BrowserExtensionTransientTab]] = [:]
    var lastState: BrowserExtensionSessionState?
    weak var browser: (any BrowserExtensionTabWindowSessionHandling)?
    weak var pageProvider: (any BrowserExtensionPageProviding)?
    var openCommandSettings: ((BrowserExtensionCommandSettingsRoute, SpaceID) -> Bool)?
    var nativeMessagingHandler: BrowserExtensionNativeMessagingHandling?
    var verifiedNativeMessagingIdentities: [ObjectIdentifier: BrowserExtensionNativeMessagingIdentity] = [:]
    var actionDidUpdate: (() -> Void)?

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
    }

    func unregister(spaceID: SpaceID) {
        guard let entry = controllers.removeValue(forKey: spaceID) else {
            return
        }
        if let adapters = tabsBySpace.removeValue(forKey: spaceID) {
            for adapter in adapters.values {
                entry.controller.didCloseTab(adapter, windowIsClosing: true)
            }
        }
        entry.controller.didCloseWindow(entry.window)
        entry.controller.delegate = nil
    }

    func reconcile(session: BrowserSession) {
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

        if oldState?.selectedSpaceID != newState.selectedSpaceID {
            if let oldID = oldState?.selectedSpaceID,
                let oldController = controllers[oldID]?.controller
            {
                oldController.didFocusWindow(nil)
            }
            if let newEntry = controllers[newState.selectedSpaceID] {
                newEntry.controller.didFocusWindow(newEntry.window)
            }
        }
        lastState = newState
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

    func tab(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionTabAdapter? {
        guard currentState?.space(spaceID)?.tab(tabID) != nil else { return nil }
        return adapter(for: tabID, in: spaceID)
    }
}
