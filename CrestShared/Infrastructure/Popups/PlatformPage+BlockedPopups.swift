import WebKit

extension BrowserPlatformPage {
    /// The notice the Site Controls affordance draws, or nil when the running
    /// engine cannot report a blocked popup at all. Only the WebKit port relays
    /// its blocker's observations, so an engine that does not declare `popups`
    /// must not present a control that can never populate.
    var blockedPopupNotice: BrowserBlockedPopupNotice? {
        guard pageEngine.registration.supports("popups") else { return nil }
        return blockedPopupState.notice
    }

    func receiveBlockedPopupMessage(_ message: WKScriptMessage) {
        if let sourceWebView = message.webView, sourceWebView !== webView {
            host?.routeBlockedPopupMessage(message)
            return
        }
        guard message.webView === webView,
            message.name == BrowserBlockedPopupContentBridge.messageHandlerName,
            message.frameInfo.isMainFrame,
            let body = message.body as? [String: Any],
            (body["version"] as? NSNumber)?.intValue == 1,
            body["event"] as? String == "blocked",
            body["userActivated"] as? Bool == false,
            let documentIdentifier = body["documentIdentifier"] as? String,
            !documentIdentifier.isEmpty,
            documentIdentifier.count <= 128,
            let frameURL = message.frameInfo.request.url,
            let origin = BrowserSiteOrigin(url: frameURL),
            let currentURL = webKitView?.url,
            BrowserSiteOrigin(url: currentURL) == origin,
            !BrowserCorePolicy.allowsAutomaticPopups(
                decision: permissionCenter.decision(
                    for: .popups,
                    origin: origin,
                    in: spaceID
                )
            )
        else { return }

        var nextState = blockedPopupState
        guard
            nextState.recordBlockedAttempt(
                documentIdentifier: documentIdentifier,
                origin: origin
            )
        else { return }
        blockedPopupState = nextState
    }

    /// A popup the engine's own blocker held back in the current document.
    func recordEngineBlockedPopup(pageURL: URL, documentIdentifier: String) {
        guard let origin = BrowserSiteOrigin(url: pageURL),
            !BrowserCorePolicy.allowsAutomaticPopups(
                decision: permissionCenter.decision(for: .popups, origin: origin, in: spaceID)
            )
        else { return }
        var nextState = blockedPopupState
        guard nextState.recordBlockedAttempt(documentIdentifier: documentIdentifier, origin: origin) else { return }
        blockedPopupState = nextState
    }

    func beginBlockedPopupNavigation() {
        var nextState = blockedPopupState
        guard nextState.clearForNavigation() else { return }
        blockedPopupState = nextState
    }

    func recordAcceptedPopup() {
        var nextState = blockedPopupState
        guard nextState.clearAfterAllowedPopup() else { return }
        blockedPopupState = nextState
    }

    func allowAutomaticPopupsForBlockedSite() {
        guard let notice = blockedPopupState.notice,
            notice.status == .blocked,
            let currentURL = displayURL ?? webKitView?.url,
            BrowserSiteOrigin(url: currentURL) == notice.origin
        else { return }

        permissionCenter.setDecision(
            .grantPersistently,
            for: .popups,
            origin: notice.origin,
            in: spaceID
        )
        synchronizePopupPermission(for: currentURL)
        // An engine that kept the blocked popups opens them now; WebKit waits
        // for the page to try again.
        if pageEngine.showBlockedPopups() { recordAcceptedPopup() }
    }

    func recordPopupPermissionSynchronized(
        allowsAutomaticPopups: Bool,
        origin: BrowserSiteOrigin?
    ) {
        guard let origin,
            blockedPopupState.notice?.origin == origin
        else { return }
        var nextState = blockedPopupState
        let didChange =
            allowsAutomaticPopups
            ? nextState.recordPermissionAllowed()
            : nextState.recordPermissionBlockedAgain()
        guard didChange else { return }
        blockedPopupState = nextState
    }
}
