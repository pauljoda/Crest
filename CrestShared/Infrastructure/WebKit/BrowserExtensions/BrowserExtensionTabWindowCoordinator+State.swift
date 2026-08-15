import Foundation
import WebKit

extension BrowserExtensionTabWindowCoordinator {

    func tabs(
        in spaceID: SpaceID,
        context: WKWebExtensionContext
    ) -> [BrowserExtensionTabAdapter] {
        guard owns(context: context, spaceID: spaceID),
            let state = currentState?.space(spaceID)
        else {
            return []
        }
        ensureAdapters(for: state)
        return state.tabs.compactMap { tabsBySpace[spaceID]?[$0.id] }
    }

    func activeTab(
        in spaceID: SpaceID,
        context: WKWebExtensionContext
    ) -> BrowserExtensionTabAdapter? {
        guard owns(context: context, spaceID: spaceID),
            let selectedID = currentState?.space(spaceID)?.selectedTabID
        else {
            return nil
        }
        return adapter(for: selectedID, in: spaceID)
    }

    func state(
        for tabID: TabID,
        in spaceID: SpaceID,
        context: WKWebExtensionContext
    ) -> BrowserExtensionTabState? {
        guard owns(context: context, spaceID: spaceID) else { return nil }
        return currentState?.space(spaceID)?.tab(tabID)
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
        for spaceID: SpaceID
    ) -> BrowserExtensionWindowGeometry {
        pageProvider?.extensionWindowGeometry(in: spaceID) ?? .unavailable
    }

    func canRevealSensitiveProperties(
        of adapter: BrowserExtensionTabAdapter,
        state: BrowserExtensionTabState,
        context: WKWebExtensionContext
    ) -> Bool {
        if context.hasPermission(.tabs, in: adapter) {
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
        return (window as? BrowserExtensionWindowAdapter)
            === controllers[spaceID]?.window
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
