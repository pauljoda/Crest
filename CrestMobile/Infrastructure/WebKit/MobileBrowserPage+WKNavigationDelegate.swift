import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

extension MobileBrowserPage: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        activeNavigation = navigation
        isAwaitingPopupNavigation = false
        beginBlockedPopupNavigation()
        beginGeolocationNavigation()
        // WebKit accepted the navigation Crest asked for, so the authorization
        // that came with it is spent.
        consumeAppInitiatedURL()
        clearNavigationFailure(preservingPendingURL: true)
        pendingServerTrustIdentity = nil
        linkPeekPressCoordinator.cancel()
        linkActivationSourceStore.removeAll()
        credentialState.didStartNavigation()
        readerModeGeneration &+= 1
        readerModeState = .unavailable
        faviconGeneration &+= 1
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        guard isCurrentNavigation(navigation) else { return }
        committedNavigationCount &+= 1
        downloadCenter.resetAutomaticDownloadSequence(in: webView)
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation?
    ) {
        guard isCurrentNavigation(navigation),
            let redirectedURL = webView.url
        else { return }
        pendingNavigationURL = redirectedURL
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard isCurrentNavigation(navigation) else { return }
        completeNavigation()
        Task { [weak self] in
            await self?.refreshReaderModeAvailability()
        }
        Task {
            await httpAuthenticationSession.authenticationSucceeded()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        switch navigationDecider.decision(
            for: navigationAction,
            isAppInitiated: isAppInitiated(navigationAction)
        ) {
        case .policy(.allow):
            break
        case .policy(let policy):
            decisionHandler(policy)
            return
        case .handOffToSystem(let url):
            // Cancelling before `prepareForNavigation` is what keeps the
            // hand-off out of the error page: nothing is pending to fail, and
            // WebKit's own cancellation error is an expected interruption.
            externalSchemeCoordinator.handOff(
                destinationURL: url,
                trigger: BrowserPopupTrigger.classify(navigationAction.navigationType),
                origin: externalSchemeCoordinator.sourceOrigin(
                    for: navigationAction,
                    currentURL: displayURL
                )
            )
            decisionHandler(.cancel)
            return
        }
        let isCommandModified = navigationAction.modifierFlags.contains(.command)
        let isOptionModified = navigationAction.modifierFlags.contains(.alternate)
        let isShiftModified = navigationAction.modifierFlags.contains(.shift)
        let isMiddleClick = navigationAction.buttonNumber.rawValue == 1 << 2
        let isUserActivatedLink = navigationAction.navigationType == .linkActivated
        let isTopLevelNavigation = navigationAction.targetFrame?.isMainFrame ?? true
        let sourcePresentation =
            isUserActivatedLink && isTopLevelNavigation
            ? linkActivationSourceStore.consume(
                destinationURL: navigationAction.request.url
            )
            : nil
        let clickIntent = BrowserLinkClickModifierPolicy.intent(
            isCommandModified: isCommandModified,
            isOptionModified: isOptionModified,
            peekModifier: BrowserLinkPreferenceStore.shared.preferences.peekClickModifier
        )
        if let request = BrowserPeekPolicy.request(
            destinationURL: navigationAction.request.url,
            context: navigationContext,
            isUserActivatedLink: isUserActivatedLink,
            isTopLevelNavigation: isTopLevelNavigation,
            isAlternateModified: clickIntent == .peek,
            isNewTabModified: clickIntent == .newTab || isMiddleClick,
            sourcePresentation: sourcePresentation
        ) {
            openPeek(request)
            decisionHandler(.cancel)
            return
        }
        switch BrowserModifiedLinkDisposition.classify(
            destinationURL: navigationAction.request.url,
            isUserActivatedLink: navigationAction.navigationType == .linkActivated,
            isCommandModified: clickIntent == .newTab,
            isShiftModified: isShiftModified,
            isMiddleClick: isMiddleClick
        ) {
        case .navigate:
            break
        case .backgroundTab(let url):
            openModifiedLink(url, spaceID, false)
            decisionHandler(.cancel)
            return
        case .foregroundTab(let url):
            openModifiedLink(url, spaceID, true)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            prepareForNavigation(to: navigationAction.request.url)
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(
            BrowserNavigationDecider.decidePolicy(
                canShowMIMEType: navigationResponse.canShowMIMEType,
                response: navigationResponse.response
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        downloadCenter.start(
            download,
            in: webView,
            profileID: profileID,
            spaceID: spaceID,
            spaceName: spaceName
        )
        discardDownloadOnlySurfaceIfNeeded()
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        downloadCenter.start(
            download,
            in: webView,
            profileID: profileID,
            spaceID: spaceID,
            spaceName: spaceName
        )
        discardDownloadOnlySurfaceIfNeeded()
    }

    func discardDownloadOnlySurfaceIfNeeded() {
        guard committedNavigationCount == 0 else { return }
        Task { @MainActor [weak self] in
            guard let self, committedNavigationCount == 0 else { return }
            host?.discardDownloadOnlyPage(self)
        }
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler:
            @escaping @MainActor @Sendable (
                URLSession.AuthChallengeDisposition,
                URLCredential?
            ) -> Void
    ) {
        #if CREST_PHYSICAL_VALIDATION
            if let credential = MobilePhysicalValidationServerTrust.credential(for: challenge) {
                completionHandler(.useCredential, credential)
                return
            }
        #endif
        if let identity = BrowserServerTrustIdentity.challengeIdentity(
            for: challenge
        ) {
            if serverTrustOverrides.isApproved(identity, for: profileID),
                let trust = challenge.protectionSpace.serverTrust
            {
                pendingServerTrustIdentity = nil
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                pendingServerTrustIdentity = identity
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }
        Task {
            let resolution = await httpAuthenticationSession.response(
                to: challenge
            ) { [spaceName] prompt in
                await MobileBrowserDialogPresenter.presentHTTPAuthentication(
                    prompt: prompt,
                    spaceName: spaceName
                )
            }
            completionHandler(resolution.disposition, resolution.credential)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        httpAuthenticationSession.authenticationFailed()
        recordWebContentTermination()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        httpAuthenticationSession.authenticationFailed()
        recordNavigationFailure(
            error,
            phase: .committed,
            navigation: navigation
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        httpAuthenticationSession.authenticationFailed()
        recordNavigationFailure(
            error,
            phase: .provisional,
            navigation: navigation
        )
    }
}
