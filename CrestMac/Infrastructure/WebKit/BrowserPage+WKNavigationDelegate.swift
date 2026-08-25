import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit
import os

extension BrowserPage: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        activeNavigation = navigation
        // Reloads and history traversal do not necessarily pass through the
        // app-level load path. Retire the old document's session as soon as
        // WebKit starts any replacement navigation.
        mediaSessionCoordinator?.prepareForNavigation()
        isAwaitingPopupNavigation = false
        beginBlockedPopupNavigation()
        beginGeolocationNavigation()
        beginHostedWebNotificationNavigation()
        // WebKit accepted the navigation Crest asked for, so the authorization
        // that came with it is spent.
        consumeAppInitiatedURL()
        clearNavigationFailure(preservingPendingURL: true)
        pendingServerTrustIdentity = nil
        credentialState.didStartNavigation()
        readerModeGeneration &+= 1
        readerModeState = .unavailable
        faviconGeneration &+= 1
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        guard isCurrentNavigation(navigation) else { return }
        mediaSessionCoordinator?.didCommitNavigation()
        committedNavigationCount += 1
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

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if let item = BrowserChromeWebStoreInstallNavigation.item(
            for: navigationAction.request.url,
            currentURL: webView.url
        ) {
            decisionHandler(.cancel)
            beginChromeWebStoreInstall(for: item)
            return
        }
        if let item = BrowserMozillaAddonsInstallNavigation.item(
            for: navigationAction.request.url,
            currentURL: webView.url
        ) {
            decisionHandler(.cancel)
            mozillaAddonsInstall.begin(for: item)
            return
        }
        let appInitiated = isAppInitiated(navigationAction)
        switch navigationDecider.decision(
            for: navigationAction,
            isAppInitiated: appInitiated
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
        let isOptionModified = navigationAction.modifierFlags.contains(.option)
        let isShiftModified = navigationAction.modifierFlags.contains(.shift)
        let isMiddleClick = BrowserMouseButtonPolicy.isMiddleButton(
            number: navigationAction.buttonNumber
        )
        let sourcePresentation =
            navigationAction.navigationType == .linkActivated
            ? peekSourcePresentation(
                for: navigationAction.request.url,
                in: webView
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
            isUserActivatedLink: navigationAction.navigationType == .linkActivated,
            isTopLevelNavigation: navigationAction.targetFrame?.isMainFrame ?? true,
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
        if BrowserExtensionExternalNavigationPolicy
            .shouldReplaceCurrentTabRuntime(
                currentURL: webView.url,
                destinationURL: navigationAction.request.url,
                isTopLevel: isTopLevelNavigation(navigationAction),
                isAppInitiated: appInitiated
            ), let destinationURL = navigationAction.request.url
        {
            decisionHandler(.cancel)
            host?.replaceExtensionPageNavigation(self, with: destinationURL)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            prepareForNavigation(to: navigationAction.request.url)
        }
        decisionHandler(.allow)
    }

    private func peekSourcePresentation(
        for destinationURL: URL?,
        in webView: WKWebView
    ) -> BrowserPeekSourcePresentation? {
        guard let window = webView.window else { return nil }
        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let pointInWebView = webView.convert(pointInWindow, from: nil)
        guard webView.bounds.contains(pointInWebView) else { return nil }

        return BrowserPeekPresentationPolicy.sourcePresentation(
            touchPoint: pointInWebView,
            in: webView.bounds.size,
            hasTopLeadingOrigin: webView.isFlipped,
            label: destinationURL?.host ?? "Link"
        )
    }

    private func downloadFeedbackSource(
        for destinationURL: URL?,
        in webView: WKWebView
    ) -> BrowserDownloadFeedbackSource? {
        guard
            let capture = downloadSourceStore.consume(
                destinationURL: destinationURL
            ),
            let window = webView.window,
            let contentView = window.contentView,
            webView.bounds.width > 0,
            webView.bounds.height > 0
        else { return nil }

        var pointInWebView = CGPoint(
            x: capture.normalizedTouchPoint.x * webView.bounds.width,
            y: capture.normalizedTouchPoint.y * webView.bounds.height
        )
        if !webView.isFlipped {
            pointInWebView.y = webView.bounds.height - pointInWebView.y
        }
        let pointInWindow = webView.convert(pointInWebView, to: nil)
        let pointInContent = contentView.convert(pointInWindow, from: nil)
        let pointFromTopLeading = CGPoint(
            x: pointInContent.x,
            y: contentView.isFlipped
                ? pointInContent.y
                : contentView.bounds.height - pointInContent.y
        )
        guard pointFromTopLeading.x.isFinite,
            pointFromTopLeading.y.isFinite
        else { return nil }
        return BrowserDownloadFeedbackSource(
            pointInGlobal: pointFromTopLeading,
            windowIdentifier: ObjectIdentifier(window)
        )
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
        let feedbackSource = downloadFeedbackSource(
            for: navigationAction.request.url,
            in: webView
        )
        downloadCenter.start(
            download,
            in: webView,
            profileID: profileID,
            spaceID: spaceID,
            spaceName: spaceName,
            isUserInitiated:
                BrowserDownloadInitiationPolicy
                .userInitiatedOverride(hasTrustedSource: feedbackSource != nil),
            feedbackSource: feedbackSource
        )
        discardDownloadOnlySurfaceIfNeeded()
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        let feedbackSource = downloadFeedbackSource(
            for: download.originalRequest?.url
                ?? navigationResponse.response.url,
            in: webView
        )
        downloadCenter.start(
            download,
            in: webView,
            profileID: profileID,
            spaceID: spaceID,
            spaceName: spaceName,
            isUserInitiated:
                BrowserDownloadInitiationPolicy
                .userInitiatedOverride(hasTrustedSource: feedbackSource != nil),
            feedbackSource: feedbackSource
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

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        mediaSessionCoordinator?.webContentProcessDidTerminate()
        credentialState.webContentProcessDidTerminate()
        httpAuthenticationSession.authenticationFailed()
        processTerminationCount += 1
        switch processRecovery.recordTermination() {
        case .reload:
            webContentFailureMessage = nil
            webView.reload()
        case .showFailure:
            webContentFailureMessage = "This page’s web process stopped repeatedly."
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
            ) { [dialogPresenter, spaceName] prompt in
                await dialogPresenter.presentHTTPAuthentication(
                    prompt: prompt,
                    spaceName: spaceName
                )
            }
            completionHandler(resolution.disposition, resolution.credential)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        #if CREST_PERFORMANCE_HARNESS
            BrowserPerformanceProcessReporter.report(webView: webView)
        #endif
        guard isCurrentNavigation(navigation) else { return }
        activeNavigation = nil
        clearNavigationFailure()
        processRecovery.recordSuccessfulNavigation()
        webContentFailureMessage = nil
        completedNavigationCount += 1
        updateUnderPageBackground()
        mediaSessionCoordinator?.didFinishNavigation()
        refreshFavicon()
        Task { [weak self] in
            await self?.refreshReaderModeAvailability()
        }
        Task {
            await httpAuthenticationSession.authenticationSucceeded()
        }
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
