#if CREST_CHROMIUM_HOST
    import AppKit

    /// The desktop Chromium adapter for one page. The engine reports its page
    /// through `ChromiumNativePage`'s observer and handlers; this decodes those
    /// reports into the page's engine-neutral events and link actions.
    @MainActor
    final class ChromiumPageAdapter: BrowserPageEngineAdapter {
        // MARK: - Variables

        let native: ChromiumNativePage
        private weak var page: BrowserPage?
        var engine: any BrowserPageEngine { native }

        /// The engine reports hovered links itself.
        private(set) lazy var linkHover: BrowserLinkHoverController? =
            BrowserLinkHoverController(contentView: native.nativeView)
        private(set) lazy var linkDrag: BrowserLinkDragController? = BrowserLinkDragController(
            nativeView: native.nativeView,
            context: { [weak self] in self?.page?.navigationContext },
            handle: { [weak self] event in self?.page?.handleLinkDrag(event) })
        private(set) lazy var pictureInPicture: (any BrowserPagePictureInPictureController)? =
            ChromiumPictureInPicturePageController(native: native)
        // Chromium presents favicons and its error pages itself; reader and
        // content blocking are unavailable.
        var readerModeSession: BrowserReaderModeSession? { nil }
        var faviconSession: BrowserFaviconSession? { nil }
        var isContentBlockingActive: Bool { false }
        /// Fills go through the engine's content scripting.
        var credentialEvaluator: BrowserCredentialSession.Evaluate? { nil }

        // MARK: - Initializers

        init(_ native: ChromiumNativePage) { self.native = native }

        // MARK: - Actions - Lifecycle

        func makeMediaSessionCoordinator(
            for page: BrowserPage,
            store: BrowserMediaSessionStore
        ) -> BrowserMediaSessionPageCoordinator? { nil }

        func attach(to page: BrowserPage, allowsCredentialAccess: Bool) {
            self.page = page
            native.permissionHandler = { [weak page] permission, origin, topLevelOrigin in
                await page?.resolveEngineSitePermission(permission, origin: origin, topLevelOrigin: topLevelOrigin)
                    ?? .dismiss
            }
            native.observer = { [weak page] report in
                guard let event = report.pageEvent else { return }
                page?.receive(event)
            }
            native.linkHandler = { [weak page] name, destination, label in
                guard let page, let action = ChromiumLinkAction(rawValue: name) else { return false }
                return page.performEngineLinkAction(action.pageAction, destination: destination, label: label)
            }
            native.contextMenuActions = { [weak page] url, selection in
                page?.contextMenuActions(linkURL: url, selectionText: selection).map(\.engineValues) ?? []
            }
            native.contextMenuAction = { [weak page] identifier, url, selection in
                page?.performContextMenuAction(
                    identifier: identifier, linkURL: url, selectionText: selection) ?? false
            }
            native.javaScriptDialogHandler = { [weak page] kind, message, defaultText, sourceURL, reply in
                guard let page else {
                    reply(false, nil)
                    return
                }
                let request = URLRequest(url: sourceURL ?? page.url ?? URL(fileURLWithPath: "/"))
                switch kind {
                case .alert:
                    page.dialogPresenter.presentAlert(message: message, request: request) {
                        reply(true, nil)
                    }
                case .confirm:
                    page.dialogPresenter.presentConfirm(message: message, request: request) {
                        reply($0, nil)
                    }
                case .prompt:
                    page.dialogPresenter.presentPrompt(
                        message: message, defaultText: defaultText, request: request
                    ) { answer in
                        reply(answer != nil, answer)
                    }
                case .beforeUnload:
                    page.dialogPresenter.presentBeforeUnload(request: request) {
                        reply($0, nil)
                    }
                }
            }
            native.httpAuthenticationHandler = { [weak page] values, reply in
                guard let page, let challenge = BrowserAuthenticationChallenge(chromium: values) else {
                    reply(nil, nil)
                    return
                }
                Task { @MainActor in
                    let decision = await page.httpAuthenticationSession.response(to: challenge) {
                        [dialogPresenter = page.dialogPresenter, spaceName = page.spaceName] prompt in
                        await dialogPresenter.presentHTTPAuthentication(prompt: prompt, spaceName: spaceName)
                    }
                    switch decision {
                    case .useCredential(let username, let password): reply(username, password)
                    case .cancel, .performDefaultHandling: reply(nil, nil)
                    }
                }
            }
            native.protectedLinkHandler = { [weak page] destination in
                page?.protectedLinkAction(to: destination)
            }
            native.modifiedLinkHandler = { [weak page, weak native] destination, modifiers, token in
                guard let page else { return (.navigate, nil) }
                return page.modifiedLinkDecision(
                    to: destination, modifiers: BrowserEngineLinkModifiers(rawValue: modifiers),
                    navigationToken: token, discard: { native?.discardNavigation(token) })
            }
            linkDrag?.observeNativeMouseDown()
        }

        func detach(from page: BrowserPage) {
            pictureInPicture?.invalidate()
            native.dispose()
        }

        func setPrivateBrowsing(_ isPrivate: Bool) { native.isPrivateBrowsing = isPrivate }
        func adoptEngineCreatedPage(_ token: String) -> Bool { native.adopt(token) }

        // MARK: - Actions - Engine-owned services

        /// Chromium's page view takes focus through its own responder chain.
        func install(_ focusRestoration: BrowserWebFocusRestorationController) {}
        /// The engine reports input as a `user_activity` event.
        func monitorUserActivity(for page: BrowserPage) {}
        /// Chromium styles visited links from its own history.
        func styleVisitedLinks(history: [BrowserHistoryEntry]) async {}
        func prepareForNavigation() {}
        /// The engine enforces site permissions itself; the page's permission
        /// session has already applied the change through `applySitePermission`.
        func sitePermissionDidChange(_ permission: SitePermission, on page: BrowserPage) {}
    }

    extension BrowserAuthenticationChallenge {
        fileprivate init?(chromium challenge: ChromiumAuthenticationChallenge) {
            guard let url = URL(string: challenge.url),
                let origin = CredentialOrigin(
                    securityProtocol: url.scheme ?? "", host: challenge.host, port: challenge.port)
            else { return nil }
            let realm = challenge.realm.flatMap { $0.isEmpty ? nil : $0 }
            let method: BrowserAuthenticationMethod
            let scope: BrowserCredentialScope
            switch challenge.method {
            case .basic:
                method = .httpBasic
                scope = .httpBasic(realm: realm)
            case .digest:
                method = .httpDigest
                scope = .httpDigest(realm: realm)
            }
            let previousFailures = challenge.previousFailureCount ?? 0
            self.init(
                authenticationMethod: method,
                isProxy: challenge.isProxy ?? false,
                previousFailureCount: previousFailures,
                protectionSpace: BrowserHTTPAuthenticationProtectionSpace(origin: origin, credentialScope: scope),
                descriptor: BrowserHTTPAuthenticationDescriptor(
                    source: BrowserCorePolicy.authenticationSourceLabel(
                        host: challenge.host, port: challenge.port, scheme: url.scheme,
                        emptyHostLabel: ProductIdentity.name),
                    realm: realm,
                    authenticationMethod: challenge.method.rawValue,
                    isSecureTransport: origin.isSecure,
                    previousFailureCount: previousFailures),
                proposedUsername: nil)
        }
    }

    extension ChromiumPageReport {
        /// The engine-neutral event this report describes, or nil when the page
        /// has nothing to do with it or its values do not describe one.
        fileprivate var pageEvent: BrowserPageEngineEvent? {
            let url = (values["url"] as? String).flatMap(URL.init(string:))
            switch event {
            case .navigationStarted: return .navigationStarted
            case .changed: return change.map { .stateChanged($0.pageState) }
            case .infoBarAdded: return BrowserEngineInfoBar(values: values).map { .infoBarAdded($0) }
            case .infoBarRemoved: return .infoBarRemoved(id: values["id"] as? Int)
            case .mediaSession: return values["body"].map { .mediaSession(body: $0) }
            case .fullscreenChanged: return .contentFullscreenChanged(values["active"] as? Bool == true)
            case .userActivity: return .userActivity
            case .linkHover: return .linkHovered(url)
            case .popupBlocked: return url.map { .popupBlocked(pageURL: $0) }
            case .favicon: return url.map { .favicon(values["data"] as? Data, source: $0) }
            case .developerPanel: return .developerPanelClosed
            case .closed: return .closeRequested
            case .creationFailed:
                return .creationFailed(message: String(localized: "Chromium couldn’t create this page."))
            case .created, .contentMessage, .storeInstall, .storeRemove, .closeCanceled: return nil
            }
        }
    }

    extension ChromiumPageChange {
        fileprivate var pageState: BrowserPageEngineState {
            let url = url.flatMap(URL.init(string:))
            let failure: BrowserPageEngineState.Failure? =
                switch pageFailure {
                case .processTerminated: .processTerminated
                case .navigationFailed:
                    .navigationFailed(BrowserNavigationFailure(chromiumNetError: errorCode ?? 0, failingURL: url))
                case nil: nil
                }
            return BrowserPageEngineState(
                url: url,
                title: title ?? "",
                isLoading: isLoading ?? false,
                security: securityState,
                themeColor: themeColor.map { argb in
                    NSColor(
                        srgbRed: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                        blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
                },
                canGoBack: canGoBack ?? false,
                canGoForward: canGoForward ?? false,
                failure: failure,
                committed: committed == true
            )
        }
    }

    /// The link actions the engine's own context menu and drag ask about.
    private enum ChromiumLinkAction: String {
        case canSearch = "can_search"
        case search
        case canPeek = "can_peek"
        case peek
        case canSplit = "can_split"
        case split
        case drag

        var pageAction: BrowserEngineLinkAction {
            switch self {
            case .canSearch: .canSearch
            case .search: .search
            case .canPeek: .canPeek
            case .peek: .peek
            case .canSplit: .canSplit
            case .split: .split
            case .drag: .drag
            }
        }
    }

    extension BrowserPage {
        /// The Chromium page behind this page, or nil when another engine hosts it.
        var chromiumPage: ChromiumNativePage? { (engineAdapter as? ChromiumPageAdapter)?.native }
    }

    extension BrowserEnginePageAdoption {
        /// Decodes the engine host's adoption offer; nil when it names no page.
        init?(chromiumValues values: [String: Any]) {
            guard let token = values["adoptionId"] as? String,
                let profileID = (values["profileId"] as? String).flatMap(UUID.init(uuidString:))
            else { return nil }
            self.init(
                token: token,
                profileID: profileID,
                sourcePageID: values["sourcePageId"] as? String,
                windowID: (values["windowId"] as? String).flatMap(UUID.init(uuidString:)).map(
                    BrowserWindowID.init(rawValue:)),
                spaceID: (values["spaceId"] as? String).flatMap(UUID.init(uuidString:)).map(SpaceID.init(rawValue:)),
                url: (values["url"] as? String).flatMap(URL.init(string:)),
                foreground: values["foreground"] as? Bool ?? true
            )
        }
    }
    /// Chromium's browser Media Session can ask the active video player to enter
    /// PiP without page JavaScript or a synthetic click. The floating surface is
    /// still Chromium-owned; this controller only follows Crest's tab lifecycle.
    @MainActor
    private final class ChromiumPictureInPicturePageController:
        BrowserPagePictureInPictureController, BrowserAutomaticPictureInPictureClient
    {
        private let native: ChromiumNativePage
        private let coordinator: BrowserAutomaticPictureInPictureCoordinator
        private var completion: (@MainActor (Bool) -> Void)?
        private var check: Task<Void, Never>?

        var isPictureInPictureActive: Bool { native.currentMediaActivity?.hasPictureInPicture == true }
        var protectsPageResidency: Bool { isPictureInPictureActive || completion != nil }
        var canAutomaticallyEnterPictureInPicture: Bool {
            native.currentMediaActivity.map { $0.isPlaying && !$0.hasPictureInPicture } == true
        }

        init(native: ChromiumNativePage, coordinator: BrowserAutomaticPictureInPictureCoordinator = .shared) {
            self.native = native
            self.coordinator = coordinator
            coordinator.register(self)
        }

        func leaveTab() {
            coordinator.request(from: self)
        }
        func returnToTab() { coordinator.cancel(self) }

        func beginAutomaticPictureInPicture(completion: @escaping @MainActor (Bool) -> Void) {
            guard native.enterPictureInPicture() else {
                completion(false)
                return
            }
            self.completion = completion
            check = Task { @MainActor [weak self] in
                // Media Session sends the request to the renderer. Check its
                // resulting browser state before releasing the reservation.
                do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                guard let self else { return }
                self.completion?(self.isPictureInPictureActive)
                self.completion = nil
                self.check = nil
            }
        }

        func cancelAutomaticPictureInPicture() {
            check?.cancel()
            check = nil
            completion?(false)
            completion = nil
        }

        func invalidate() {
            coordinator.cancel(self)
        }
    }
#endif
