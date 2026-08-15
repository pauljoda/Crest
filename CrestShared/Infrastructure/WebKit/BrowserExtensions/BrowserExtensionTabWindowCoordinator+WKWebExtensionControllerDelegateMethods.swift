import WebKit

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
        return [entry.window]
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard
            let (spaceID, entry) = verifiedSpaceAndEntry(
                controller: controller,
                context: extensionContext
            ), currentState?.selectedSpaceID == spaceID
        else {
            return nil
        }
        return entry.window
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
                pageProvider?.select(session: session)
            }
            reconcile(session: session)
        }
        completionHandler(entry.window, nil)
    }
}
