import Foundation
import WebKit

extension BrowserExtensionTabWindowCoordinator {
    func activate(
        tabID: TabID,
        spaceID: SpaceID,
        completionHandler: @escaping (Error?) -> Void
    ) {
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
        guard let browser,
            browser.loadExtensionURL(url, in: tabID, spaceID: spaceID)
        else {
            completionHandler(adapterError(.tabUnavailable))
            return
        }
        pageProvider?.extensionWebView(for: tabID, in: spaceID)?
            .load(URLRequest(url: url))
        reconcile(session: browser.session)
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
        if selected {
            pageProvider?.select(session: session)
        }
        completionHandler(adapter(for: tabID, in: spaceID), nil)
    }
}
