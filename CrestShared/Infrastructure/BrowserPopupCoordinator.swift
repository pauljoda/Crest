import Foundation
import WebKit

@MainActor
final class BrowserPopupCoordinator {
    typealias Prompt =
        @MainActor (
            BrowserSiteOrigin,
            URL,
            String
        ) async -> BrowserSitePermissionPromptResponse

    /// Routes a popup destination another application owns into the
    /// external-scheme consent path.
    typealias ExternalSchemeHandOff =
        @MainActor (
            URL,
            BrowserPopupTrigger,
            BrowserSiteOrigin?
        ) -> Void

    private let spaceID: SpaceID
    private let spaceName: String
    private let permissionCenter: BrowserSitePermissionCenter
    private let prompt: Prompt
    private let openNewTab: (URL) -> Void
    private let handOffExternalScheme: ExternalSchemeHandOff

    init(
        spaceID: SpaceID,
        spaceName: String,
        permissionCenter: BrowserSitePermissionCenter,
        prompt: @escaping Prompt,
        openNewTab: @escaping (URL) -> Void,
        handOffExternalScheme: @escaping ExternalSchemeHandOff = { _, _, _ in }
    ) {
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.permissionCenter = permissionCenter
        self.prompt = prompt
        self.openNewTab = openNewTab
        self.handOffExternalScheme = handOffExternalScheme
    }

    /// Resolves one new-window request while WebKit waits. `adopt` receives the
    /// requested URL — nil for `window.open()` without a destination — and
    /// returns the web view WebKit created from its own configuration, or nil
    /// when the opener cannot host an adopted popup (a Peek or Quick Window
    /// lease, or a pool without a tab host). A declined adoption still opens the
    /// destination as a plain tab so the request is never silently dropped.
    func resolveOpen(
        for navigationAction: WKNavigationAction,
        currentURL: URL?,
        adopt: (URL?) -> WKWebView?
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let destinationURL = navigationAction.request.url

        // The scheme settles first, before any tab exists. A destination another
        // app owns goes straight to the hand-off consent path, and one nothing may
        // open is dropped — neither leaves a tab behind.
        switch BrowserPopupSchemeRouting.classify(destinationURL: destinationURL) {
        case .popupPolicy:
            break
        case .blocked:
            return nil
        case .handOffToSystem(let url):
            handOffExternalScheme(
                url,
                BrowserPopupTrigger.classify(navigationAction.navigationType),
                sourceOrigin(for: navigationAction, currentURL: currentURL)
            )
            return nil
        }

        switch disposition(for: navigationAction, currentURL: currentURL) {
        case .open:
            if let popupWebView = adopt(destinationURL) {
                return popupWebView
            }
            if let destinationURL {
                openNewTab(destinationURL)
            }
            return nil
        case .deny:
            return nil
        case .prompt:
            // A scripted popup with no destination has nothing to ask about, so
            // it is declined rather than described to the user as a blank window.
            guard let destinationURL,
                let origin = sourceOrigin(
                    for: navigationAction,
                    currentURL: currentURL
                )
            else { return nil }
            requestPermission(origin: origin, destinationURL: destinationURL)
            return nil
        }
    }

    private func disposition(
        for navigationAction: WKNavigationAction,
        currentURL: URL?
    ) -> BrowserPopupDisposition {
        let trigger = BrowserPopupTrigger.classify(navigationAction.navigationType)
        guard trigger == .scripted else { return .open }
        guard
            let origin = sourceOrigin(
                for: navigationAction,
                currentURL: currentURL
            )
        else {
            return .deny
        }
        return Self.disposition(
            trigger: trigger,
            decision: permissionCenter.decision(
                for: .popups,
                origin: origin,
                in: spaceID
            )
        )
    }

    /// The popup policy itself: a link click or form submission is the user
    /// asking for a window, while script-driven requests answer to the
    /// per-origin pop-up permission.
    nonisolated static func disposition(
        trigger: BrowserPopupTrigger,
        decision: BrowserSitePermissionDecision
    ) -> BrowserPopupDisposition {
        guard trigger == .scripted else { return .open }
        switch decision {
        case .grantForSession, .grantPersistently:
            return .open
        case .denyForSession, .denyPersistently:
            return .deny
        case .ask:
            return .prompt
        }
    }

    /// A prompt cannot answer while `createWebViewWith` is on the stack, so an
    /// allowed popup arrives as a plain tab. WebKit has already discarded its
    /// configuration by then, which is why this path cannot adopt.
    private func requestPermission(
        origin: BrowserSiteOrigin,
        destinationURL: URL
    ) {
        Task { [prompt, spaceName, weak self] in
            guard let self else { return }
            let response = await prompt(origin, destinationURL, spaceName)
            switch response {
            case .allowOnce:
                self.openNewTab(destinationURL)
            case .grantPersistently:
                self.permissionCenter.setDecision(
                    .grantPersistently,
                    for: .popups,
                    origin: origin,
                    in: self.spaceID
                )
                self.openNewTab(destinationURL)
            case .denyPersistently:
                self.permissionCenter.setDecision(
                    .denyPersistently,
                    for: .popups,
                    origin: origin,
                    in: self.spaceID
                )
            }
        }
    }

    /// The origin that asked for the window. WebKit annotates `sourceFrame` as
    /// non-null and every real popup has one, so it is read as an optional purely
    /// so a missing frame falls back to the page the user is looking at instead of
    /// trapping. A frame WebKit reports without a host — `about:blank`, a
    /// sandboxed frame — takes the same fallback, which is the origin a prompt
    /// would name anyway.
    private func sourceOrigin(
        for navigationAction: WKNavigationAction,
        currentURL: URL?
    ) -> BrowserSiteOrigin? {
        if let provider = navigationAction
            as? any BrowserNavigationActionSourceOriginProviding
        {
            return provider.browserSourceOrigin
                ?? currentURL.flatMap(BrowserSiteOrigin.init(url:))
        }
        let sourceFrame: WKFrameInfo? = navigationAction.sourceFrame
        if let sourceFrame {
            let frameOrigin = BrowserSiteOrigin(sourceFrame.securityOrigin)
            if !frameOrigin.host.isEmpty {
                return frameOrigin
            }
        }
        return currentURL.flatMap(BrowserSiteOrigin.init(url:))
    }
}
