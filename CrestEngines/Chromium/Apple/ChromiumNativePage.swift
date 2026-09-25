#if CREST_CHROMIUM_HOST
    import AppKit
    import Observation
    import PDFKit

    /// Hosts the view of one Chromium page and makes the page's direct calls:
    /// history, find, zoom, capture and the rest. Chromium's C++ binding creates,
    /// loads and closes the page when the core asks, under the identity the
    /// core gave it, and tells the core what it does; this reports nothing.
    @Observable @MainActor
    final class ChromiumNativePage: BrowserPageEngine {
        let registration = BrowserEngineRegistration.chromium
        /// The core's identity for this page.
        let pageID: UUID
        /// The name the engine uses for this page: the core's identity.
        let id: String
        let surface = ChromiumNativePageView()
        var isPrivateBrowsing: Bool
        /// The profile of the page's Space, once its owner names it.
        var profileID: UUID?
        /// The browser operations this page may ask for, such as the Space a
        /// Chrome Web Store listing installs into. Weak: the composition owns it.
        private weak var hostCommands: (any BrowserEngineHostCommands)?
        /// A Settings page of the engine's own, such as its flags page, which no
        /// tab owns and the core never hears of: it creates itself once its view
        /// is in a window. TRANSITIONAL until such pages open through the core.
        private let isStandalone: Bool
        var observer: (ChromiumPageReport) -> Void
        var linkHandler: (String, URL, String) -> Bool = { _, _, _ in false }
        var contextMenuActions: (URL?, String?) -> [[String: String]] = { _, _ in [] }
        var contextMenuAction: (String, URL?, String?) -> Bool = { _, _, _ in false }
        var httpAuthenticationHandler: (ChromiumAuthenticationChallenge, @escaping (String?, String?) -> Void) -> Void =
            {
                _, reply in reply(nil, nil)
            }
        var javaScriptDialogHandler:
            (
                ChromiumJavaScriptDialogKind, String, String, URL?, @escaping (Bool, String?) -> Void
            ) -> Void = { _, _, _, _, reply in reply(false, nil) }
        var protectedLinkHandler: (URL) -> (() -> Void)? = { _ in nil }
        var modifiedLinkHandler: (URL, Int, String) -> (LinkNavigationDecision, (() -> Void)?) = { _, _, _ in
            (.navigate, nil)
        }
        private var host: (any CrestChromiumEngineHost)?
        /// What a standalone page loads once it exists.
        private var requestedURL: URL?
        private var zoom: CGFloat = 1
        private var creating = false
        private var created = false
        private var disposed = false

        /// A page the core opened, which Chromium's binding creates.
        init(id: UUID, host: any CrestChromiumEngineHost, hostCommands: (any BrowserEngineHostCommands)?) {
            pageID = id
            self.id = id.uuidString
            self.host = host
            self.hostCommands = hostCommands
            isPrivateBrowsing = false
            isStandalone = false
            observer = { _ in }
            surface.page = self
            host.observePage(self.id) { [weak self] event, values in
                MainActor.assumeIsolated { self?.receive(event, values: values) }
            }
        }

        /// A Settings page of the engine's own in `profileID`, which creates
        /// itself.
        init(standaloneIn profileID: UUID) {
            let id = UUID()
            pageID = id
            self.id = id.uuidString
            self.profileID = profileID
            isPrivateBrowsing = false
            isStandalone = true
            observer = { _ in }
            surface.page = self
        }

        var nativeView: NSView { surface }
        func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool {
            guard !isStandalone, !created, !disposed, let host,
                navigation.implementation == registration.implementationId,
                UUID(uuidString: navigation.token) != nil
            else { return false }
            return host.stageNavigation(navigation.token, page: id, url: url.absoluteString)
        }
        func discardNavigation(_ token: String) {
            (host ?? CrestChromiumRoot.engineHost)?.discardPendingNavigation(token)
        }
        func showInspector() -> Bool {
            guard created, !disposed, let host else { return false }
            return host.command(ChromiumPageHostCommand.inspect.rawValue, page: id, url: nil)
        }
        func toggleInspector(_ panel: BrowserDeveloperPanel, current: BrowserDeveloperPanel?)
            -> BrowserWebInspectorToggleResult
        {
            guard created, !disposed, let host else { return .unavailable }
            let isOpen = host.command(ChromiumPageHostCommand.inspectVisible.rawValue, page: id, url: nil)
            if isOpen, current == panel {
                return host.command(ChromiumPageHostCommand.inspectClose.rawValue, page: id, url: nil)
                    ? .closed : .unavailable
            }
            let command: ChromiumPageHostCommand
            switch panel {
            case .console: command = .inspectConsole
            case .elements: command = .inspectElements
            case .network: command = .inspectNetwork
            }
            guard host.command(command.rawValue, page: id, url: nil) else { return .unavailable }
            // Chromium selects a starting panel for Console and Elements only. A
            // Network request opens DevTools wherever it was, so report no panel
            // rather than claiming a selection the engine did not make.
            return .opened(panel == .network ? nil : panel)
        }
        var interactionState: Data? {
            guard created, !disposed, let host, let state = host.interactionState(forPage: id) else { return nil }
            return BrowserEngineInteractionState(engine: .chromium, version: host.engineVersion(), payload: state)
                .encoded()
        }

        /// The binding restores the history in place of the page's first load,
        /// once the page exists.
        func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool {
            guard !isStandalone, !disposed, let host,
                let payload = BrowserEngineInteractionState.payload(
                    state, engine: .chromium, version: host.engineVersion())
            else { return false }
            return host.restorePage(id, interactionState: payload, expectedURL: url.absoluteString)
        }
        private(set) var backHistory: [BrowserNavigationHistoryItem] = []
        private(set) var forwardHistory: [BrowserNavigationHistoryItem] = []
        private(set) var currentURL: URL?
        private(set) var canGoBack = false
        private(set) var canGoForward = false
        /// Every `changed` report carries the page's history, loading and failure
        /// state, so the page reads them from it.
        var reportsNavigationState: Bool { true }
        var currentMediaActivity: PageMediaActivity? {
            guard created, !disposed, let values = host?.mediaActivity(forPage: id) else { return nil }
            var activity: PageMediaActivity = []
            if values["playing"] as? Bool == true { activity.insert(.playing) }
            if values["capturing"] as? Bool == true { activity.insert(.capturing) }
            if values["pictureInPicture"] as? Bool == true { activity.insert(.pictureInPicture) }
            return activity
        }
        func mediaActivity() async -> PageMediaActivity? { currentMediaActivity }
        func enterPictureInPicture() -> Bool {
            guard created, !disposed, let host else { return false }
            return host.command(ChromiumPageHostCommand.pictureInPictureEnter.rawValue, page: id, url: nil)
        }
        func transferOwnership(to windowID: BrowserWindowID) -> Bool {
            guard created, !disposed, let host else { return false }
            return host.preparePage(id, forWindow: windowID.uuidString)
        }

        func capture(rect: CGRect?, width: CGFloat?, completion: @escaping @MainActor (NSImage?) -> Void) {
            guard created, !disposed, let host else {
                completion(nil)
                return
            }
            host.capturePage(id, rect: rect ?? .zero, width: width ?? 0) { image in
                MainActor.assumeIsolated { completion(image) }
            }
        }
        func load(_ request: URLRequest) {
            guard let url = request.url else { return }
            load(url)
        }
        func navigateHistory(by offset: Int) {
            guard created, !disposed, offset != 0 else { return }
            _ = host?.command(ChromiumPageHostCommand.history.rawValue, page: id, url: String(offset))
        }
        func reload(bypassingCache: Bool) {
            command(bypassingCache ? .reloadFromOrigin : .reload)
        }
        func stop() { command(.stop) }

        /// The app's own load of `url`, which the binding runs as it runs the
        /// core's LoadPage.
        func load(_ url: URL) {
            guard !disposed else { return }
            guard isStandalone else {
                host?.loadPage(id, url: url.absoluteString)
                return
            }
            requestedURL = url
            if created { navigatePendingURL() } else { attachIfPossible() }
        }

        func attachIfPossible() {
            guard !disposed, let windowID = surface.window?.identifier?.rawValue,
                let host = CrestChromiumRoot.engineHost
            else { return }
            self.host = host
            if created {
                guard host.preparePage(id, forWindow: windowID), let view = host.view(forPage: id) else { return }
                if view.superview !== surface {
                    view.removeFromSuperview()
                    view.frame = surface.bounds
                    view.autoresizingMask = [.width, .height]
                    surface.addSubview(view)
                }
                host.didAttachPage(id, window: windowID)
                return
            }
            // The binding creates a page the core opened; only a standalone page
            // creates itself.
            guard isStandalone, !creating, let profileID else { return }
            creating = true
            if !host.createPage(
                id, profile: profileID.uuidString, window: windowID, privateMode: false, sourceProfile: nil,
                observer: { [weak self] event, values in
                    MainActor.assumeIsolated { self?.receive(event, values: values) }
                })
            {
                creating = false
                observer(ChromiumPageReport(.creationFailed))
            }
        }

        /// Makes the page the engine offered as `token` this page, which the
        /// binding then follows instead of creating one.
        func adopt(_ token: String) -> Bool {
            guard !isStandalone, !created, !disposed, let host else { return false }
            return host.adoptPage(token, asPage: id) { [weak self] event, values in
                MainActor.assumeIsolated { self?.receive(event, values: values) }
            }
        }

        /// The engine's find wraps at the end of the page, as Crest's find always
        /// does, and counts every match.
        func performFind(
            _ query: String, configuration: BrowserFindConfiguration,
            completion: @escaping @MainActor (BrowserFindResult) -> Void
        ) {
            guard created, !disposed, let host,
                host.find(
                    inPage: id, query: query, backwards: configuration.backwards,
                    caseSensitive: configuration.caseSensitive,
                    completion: { total, active in
                        MainActor.assumeIsolated {
                            completion(BrowserFindResult(matchCount: total, activeMatch: active))
                        }
                    })
            else {
                completion(.notFound)
                return
            }
        }

        // MARK: Content bridges

        private var contentScripts: [BrowserContentScript] = []
        private var contentReceivers: [String: @MainActor (BrowserContentMessage) -> Void] = [:]
        var contentScripting: (any BrowserPageContentScripting)? { self }

        private func receiveContentMessage(_ values: [String: Any]) {
            // The body is whatever the bridge posted, so it stays an opaque value.
            guard let message = ChromiumHostPayload.decode(ChromiumContentMessagePayload.self, from: values),
                let receive = contentReceivers[message.handler],
                let body = try? JSONSerialization.jsonObject(with: Data(message.body.utf8), options: .fragmentsAllowed)
            else { return }
            receive(
                BrowserContentMessage(
                    handlerName: message.handler, body: body,
                    frame: BrowserContentFrame(
                        isMainFrame: message.isMainFrame == true, securityProtocol: message.protocol,
                        host: message.host, port: message.port ?? 0, handle: message.frame as NSString)))
        }

        struct ContentSetting: Identifiable {
            let id: String
            let label: String
            var value: Int
            let supportsAsk: Bool
        }
        var permissions: [ContentSetting] {
            (host?.permissions(forPage: id) ?? []).compactMap { item in
                guard let id = item["id"] as? String, let label = item["label"] as? String,
                    let value = item["value"] as? Int
                else { return nil }
                return ContentSetting(
                    id: id, label: label, value: value, supportsAsk: item["supportsAsk"] as? Bool ?? false)
            }
        }
        func setPermission(_ permission: String, value: Int) -> Bool {
            host?.setPermission(permission, page: id, value: value) ?? false
        }

        // Chromium's content-setting values: 1 allows; 0 clears the site's own
        // setting, which leaves the engine's default of blocking.
        func applyAutomaticPopups(_ allowed: Bool) -> Bool {
            guard created, !disposed else { return true }
            _ = setPermission("popups", value: allowed ? 1 : 0)
            return true
        }

        func respondToInfoBar(_ barID: Int, response: String) -> Bool {
            guard created, !disposed, let host else { return false }
            return host.command(ChromiumPageHostCommand.infoBar.rawValue, page: id, url: "\(response):\(barID)")
        }

        /// Rebuilt from the chain the engine verified, so the system certificate
        /// sheet can show it. The trust carries an SSL policy for the page's host.
        var serverTrust: SecTrust? {
            guard created, !disposed, let host, let chain = host.certificateChain(forPage: id) as [NSData]?,
                !chain.isEmpty
            else { return nil }
            let certificates = chain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            guard certificates.count == chain.count else { return nil }
            var trust: SecTrust?
            let policy = SecPolicyCreateSSL(true, pageHost as CFString?)
            guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess else {
                return nil
            }
            return trust
        }
        private var pageHost: String?
        private(set) var mediaSessionLocation: String?
        var mediaSessionTransport: (any BrowserMediaSessionTransport)? { self }

        /// The host keys the content settings it enforces by the permissions'
        /// names: 1 allows, 2 blocks and 0 clears the site's own setting.
        func applySitePermission(_ permission: SitePermission, allowed: Bool?) -> Bool {
            guard Self.enforcedPermissions.contains(permission) else { return false }
            guard created, !disposed else { return true }
            _ = setPermission(permission.name, value: allowed.map { $0 ? 1 : 2 } ?? 0)
            return true
        }

        private static let enforcedPermissions = SitePermission.all.filter(\.isEngineEnforced)

        /// Answers the engine's site permission requests from Crest's record and
        /// prompt.
        var permissionHandler: ((SitePermission, SiteOrigin, SiteOrigin) async -> BrowserEnginePermissionResponse)?

        /// The engine clears the site its page is showing.
        func clearSiteData(for url: URL) async -> Bool {
            guard created, !disposed, let host else { return false }
            return await withCheckedContinuation { continuation in
                host.clearSiteData(page: id) { cleared in continuation.resume(returning: cleared) }
            }
        }

        func refreshFavicon() {
            guard created, !disposed else { return }
            _ = host?.command(ChromiumPageHostCommand.faviconRefresh.rawValue, page: id, url: nil)
        }

        func showBlockedPopups() -> Bool {
            guard created, !disposed, let host else { return false }
            return host.command(ChromiumPageHostCommand.showBlockedPopups.rawValue, page: id, url: nil)
        }

        struct ExtensionAction: Identifiable {
            let id: String
            let name: String
            let badge: String
            let icon: NSImage?
            let pinned: Bool
        }

        var extensions: [ExtensionAction] {
            guard created, !disposed else { return [] }
            return (host?.extensions(forPage: id) ?? []).compactMap { item in
                guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
                return ExtensionAction(
                    id: id, name: name, badge: item["badge"] as? String ?? "", icon: item["icon"] as? NSImage,
                    pinned: item["pinned"] as? Bool ?? false)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        func runExtension(_ extensionID: String, anchor: BrowserExtensionPopupAnchor? = nil) {
            guard created, !disposed else { return }
            let anchor =
                anchor ?? BrowserExtensionPopupAnchor(screenPoint: NSEvent.mouseLocation, sourceWindow: surface.window)
            guard let source = anchor.presentationSource(fallbackWindow: surface.window) else { return }
            if host?.runExtension(extensionID, page: id, anchorView: source.view, anchorRect: source.rect) != true {
                CrestChromiumRoot.showNativeNotice(
                    "This extension action is unavailable on this page.", icon: "puzzlepiece.extension")
            }
        }

        /// Whether `extensionID` has a side panel entry for this page's own tab.
        func hasSidePanel(_ extensionID: String) -> Bool {
            guard created, !disposed, let host else { return false }
            return host.hasSidePanel(extensionID, page: id)
        }

        /// Creates the panel document and returns its view for the core to mount.
        /// `closed` runs when the panel or its extension host goes away on its own.
        func openSidePanel(_ extensionID: String, closed: @escaping () -> Void) -> NSView? {
            guard created, !disposed, let host else { return nil }
            return host.openSidePanel(extensionID, page: id, closed: closed)
        }

        func closeSidePanel() {
            guard created, !disposed else { return }
            host?.closeSidePanel(page: id)
        }

        /// Mounts, relayouts or removes the docked DevTools frontend the engine is
        /// offering for this page.
        ///
        /// A docked inspector belongs to the card it inspects, not to the window:
        /// the frontend is a subview of this page's own surface, below the page so
        /// the page can be drawn on top of it at the rectangle the frontend asked
        /// for. Undocking withdraws the offer — Chromium then opens the window the
        /// user asked for — and so does closing the inspector by any route.
        func refreshDevTools() {
            guard !disposed, let host else { return }
            surface.devToolsView = host.devToolsView(page: id)
            surface.layoutEngineView()
        }

        /// The inspector for this page is going away, whatever closed it. The core
        /// clears its developer-panel selection so the next Console or Elements
        /// command opens an inspector instead of trying to close a closed one.
        func developerPanelDidClose() {
            guard !disposed else { return }
            observer(ChromiumPageReport(.developerPanel))
        }

        /// The Chrome Web Store listing this page is showing asked Crest to install
        /// or remove the extension it is about. The engine has already checked that
        /// the extension is the one the page's own URL names, and the destination is
        /// this page's own Space — a listing can never reach another Space or a
        /// private window, which keeps no persistent extension state.
        private func performStoreRequest(_ event: ChromiumPageEvent, _ values: [String: Any]) {
            let store = CrestChromiumRoot.extensions
            guard !isPrivateBrowsing, let id = values["id"] as? String, let profileID,
                let space = hostCommands?.extensionSpace(forProfile: profileID)
            else {
                refreshStoreState()
                return
            }
            let refresh: @MainActor () -> Void = { [weak self] in self?.refreshStoreState() }
            if event == .storeRemove {
                store.confirmRemoval(id, in: space, completion: refresh)
            } else {
                store.install(id, in: space, anchor: surface, completion: refresh)
            }
        }

        /// Restates the listing's install button from Chromium's own registry once
        /// an install review has finished, been canceled, or was never offered.
        private func refreshStoreState() {
            guard created, !disposed else { return }
            _ = host?.command(ChromiumPageHostCommand.storeState.rawValue, page: id, url: nil)
        }

        static func webStoreExtensionID(_ url: URL?) -> String? {
            guard let url, url.scheme == "https", url.host == "chromewebstore.google.com",
                url.pathComponents.count >= 3, url.pathComponents[1] == "detail",
                let id = url.pathComponents.last, id.count == 32,
                id.allSatisfy({ ("a"..."p").contains(String($0)) })
            else { return nil }
            return id
        }

        func setZoom(_ zoom: CGFloat) {
            self.zoom = zoom
            if created { _ = host?.command(ChromiumPageHostCommand.zoom.rawValue, page: id, url: String(Double(zoom))) }
        }

        func detach() { if created { host?.didDetachPage(id) } }

        private func command(_ command: ChromiumPageHostCommand) {
            guard created, !disposed else { return }
            _ = host?.command(command.rawValue, page: id, url: nil)
        }

        /// The page's owner let it go. The core's ClosePage has the binding
        /// close what the engine holds; only a standalone page closes itself.
        func dispose() {
            guard !disposed else { return }
            disposed = true
            surface.devToolsView = nil
            for subview in surface.subviews { subview.removeFromSuperview() }
            if isStandalone { host?.disposePages([id], windows: [], releaseProfiles: []) }
            host = nil
        }

        /// Loads what a standalone page was asked to, once it exists.
        private func navigatePendingURL() {
            guard isStandalone, let requestedURL else { return }
            self.requestedURL = nil
            _ = host?.command(
                ChromiumPageHostCommand.navigate.rawValue, page: id,
                url: ChromiumInternalURL.engine(requestedURL.absoluteString))
        }

        private func history(_ entries: [ChromiumPageChange.HistoryEntry]?) -> [BrowserNavigationHistoryItem] {
            (entries ?? []).compactMap { entry in
                guard entry.depth > 0, let url = URL(string: ChromiumInternalURL.presented(entry.url)) else {
                    return nil
                }
                let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return BrowserNavigationHistoryItem(
                    depth: entry.depth,
                    title: title.isEmpty ? url.host() ?? url.absoluteString : title, url: url)
            }
        }

        /// Decodes a host observation once. An event this build does not know is
        /// dropped: the page has nothing to do with it.
        private func receive(_ name: String, values: [String: Any]) {
            guard !disposed, let event = ChromiumPageEvent(rawValue: name) else { return }
            switch event {
            case .contentMessage:
                receiveContentMessage(values)
            case .changed:
                guard let change = ChromiumHostPayload.decode(ChromiumPageChange.self, from: values) else { return }
                receive(change)
            default:
                receive(ChromiumPageReport(event, values: ChromiumInternalURL.presentedValues(values)))
            }
        }

        private func receive(_ change: ChromiumPageChange) {
            backHistory = history(change.backHistory)
            forwardHistory = history(change.forwardHistory)
            canGoBack = change.canGoBack ?? false
            canGoForward = change.canGoForward ?? false
            currentURL = change.url.map(ChromiumInternalURL.presented).flatMap(URL.init(string:))
            if change.committed == true { surface.layoutEngineView() }
            pageHost = change.url.flatMap(URL.init(string:))?.host()
            mediaSessionLocation = change.url
            observer(ChromiumPageReport(.changed, change: change.presented()))
        }

        private func receive(_ report: ChromiumPageReport) {
            let event = report.event
            let values = report.values
            if event == .created {
                created = true
                creating = false
                for script in contentScripts {
                    _ = host?.addContentScript(script.source, page: id, mainFrameOnly: script.mainFrameOnly)
                }
                host?.setPermissionHandler(page: id) { [weak self] request, reply in
                    MainActor.assumeIsolated {
                        guard let self, let handler = self.permissionHandler,
                            let permission = (request["permission"] as? String).flatMap(
                                SitePermission.named),
                            let origin = (request["origin"] as? String).flatMap(URL.init(string:)).flatMap(
                                SiteOrigin.init(url:))
                        else {
                            reply(BrowserEnginePermissionResponse.dismiss.hostCode)
                            return
                        }
                        let topLevel =
                            (request["topLevelOrigin"] as? String).flatMap(URL.init(string:))
                            .flatMap(SiteOrigin.init(url:)) ?? origin
                        Task { @MainActor in reply(await handler(permission, origin, topLevel).hostCode) }
                    }
                }
                host?.setLinkHandler(page: id) { [weak self] action, address, label in
                    MainActor.assumeIsolated {
                        guard let self, !self.disposed, let url = URL(string: address) else { return false }
                        return self.linkHandler(action, url, label)
                    }
                }
                host?.setContextMenuHandler(
                    page: id,
                    provider: { [weak self] address, selection in
                        MainActor.assumeIsolated {
                            guard let self, !self.disposed else { return [] }
                            let url = address == "about:blank" ? nil : URL(string: address)
                            return self.contextMenuActions(url, selection.isEmpty ? nil : selection)
                        }
                    },
                    action: { [weak self] identifier, address, selection in
                        MainActor.assumeIsolated {
                            guard let self, !self.disposed else { return false }
                            let url = address == "about:blank" ? nil : URL(string: address)
                            return self.contextMenuAction(identifier, url, selection.isEmpty ? nil : selection)
                        }
                    })
                host?.setJavaScriptDialogHandler(page: id) { [weak self] kind, message, defaultText, address, reply in
                    MainActor.assumeIsolated {
                        guard let self, !self.disposed else {
                            reply(false, nil)
                            return
                        }
                        guard let kind = ChromiumJavaScriptDialogKind(rawValue: kind) else {
                            reply(false, nil)
                            return
                        }
                        self.javaScriptDialogHandler(kind, message, defaultText, URL(string: address), reply)
                    }
                }
                host?.setHTTPAuthenticationHandler(page: id) { [weak self] challenge, reply in
                    MainActor.assumeIsolated {
                        guard let self, !self.disposed,
                            let challenge = ChromiumHostPayload.decode(
                                ChromiumAuthenticationChallenge.self, from: challenge)
                        else {
                            reply(nil, nil)
                            return
                        }
                        self.httpAuthenticationHandler(challenge, reply)
                    }
                }
                host?.setProtectedLinkHandler(page: id) { [weak self] address in
                    var deferred: CrestDeferredNavigation?
                    MainActor.assumeIsolated {
                        guard let self, !self.disposed, let url = URL(string: address),
                            let action = self.protectedLinkHandler(url)
                        else { return }
                        deferred = { [weak self] in
                            MainActor.assumeIsolated {
                                guard let self, !self.disposed else { return }
                                action()
                            }
                        }
                    }
                    return deferred
                }
                host?.setModifiedLinkHandler(page: id) { [weak self] address, modifiers, token, reply in
                    MainActor.assumeIsolated {
                        guard let self, !self.disposed, let url = URL(string: address) else {
                            reply(LinkNavigationDecision.navigate.name, nil)
                            return
                        }
                        let (decision, action) = self.modifiedLinkHandler(url, Int(modifiers), token)
                        var deferred: CrestDeferredNavigation?
                        if let action {
                            deferred = { [weak self] in
                                MainActor.assumeIsolated {
                                    guard let self, !self.disposed else { return }
                                    action()
                                }
                            }
                        }
                        reply(decision.name, deferred)
                    }
                }
                attachIfPossible()
                setZoom(zoom)
                navigatePendingURL()
            } else if event == .creationFailed {
                creating = false
            } else if event == .storeInstall || event == .storeRemove {
                performStoreRequest(event, values)
            } else if event == .linkUnavailable {
                // A stale link is never retried as a bare address, which would
                // lose the initiating frame's security and referrer.
                observer(
                    ChromiumPageReport(
                        .changed,
                        change: ChromiumPageChange(
                            url: currentURL?.absoluteString, isLoading: false,
                            failure: String(
                                localized: "This link is no longer available. Open it again from its original page."))))
                return
            }
            observer(report)
        }
    }

    extension ChromiumNativePage: BrowserPageDocumentServices {
        var documentServices: (any BrowserPageDocumentServices)? { self }
        var archiveFormat: BrowserPageArchiveFormat { .mhtml }

        func fullPageSnapshot(width: CGFloat?) async throws -> NSImage {
            let backingScale = surface.window?.backingScaleFactor ?? 1
            let data = try await exportData(format: "png", width: width ?? 0)
            guard let image = NSImage(data: data) else {
                throw BrowserPageExportError.renderingFailed("The page capture could not be decoded.")
            }
            // Chromium returns device pixels; AppKit composes the capture in points.
            let logicalWidth = width ?? image.size.width / backingScale
            image.size = NSSize(width: logicalWidth, height: image.size.height * logicalWidth / image.size.width)
            return image
        }

        func pdfData() async throws -> Data { try await exportData(format: "pdf") }
        func webArchiveData() async throws -> Data { try await exportData(format: "mhtml") }

        func printOperation(with info: NSPrintInfo) async throws -> NSPrintOperation {
            let data = try await pdfData()
            guard let document = PDFDocument(data: data),
                let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true)
            else {
                throw BrowserPageExportError.renderingFailed("The page could not be prepared for printing.")
            }
            return operation
        }

        private func exportData(format: String, width: CGFloat = 0) async throws -> Data {
            guard created, !disposed, let host else { throw BrowserPageExportError.pageUnavailable }
            return try await withCheckedThrowingContinuation { continuation in
                host.exportPage(id, format: format, width: width) { data, error in
                    MainActor.assumeIsolated {
                        if let data {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(
                                throwing: BrowserPageExportError.renderingFailed(
                                    error ?? "The page could not be exported."))
                        }
                    }
                }
            }
        }
    }

    @MainActor
    final class ChromiumNativePageView: NSView, BrowserNativePageSurfaceLifecycle {
        weak var page: ChromiumNativePage?
        /// The docked DevTools frontend, while one is offered for this page. It is
        /// kept below the engine's page view so the page is drawn on top of it,
        /// which is the arrangement the resizing strategy is expressed in.
        var devToolsView: NSView? {
            didSet {
                guard devToolsView !== oldValue else { return }
                oldValue?.removeFromSuperview()
                guard let devToolsView else { return }
                devToolsView.autoresizingMask = []
                if let engineView {
                    addSubview(devToolsView, positioned: .below, relativeTo: engineView)
                } else {
                    addSubview(devToolsView)
                }
            }
        }
        /// The engine's page view. The DevTools frontend is a sibling, so the page
        /// is whichever subview is not it.
        private var engineView: NSView? {
            subviews.first { $0 !== devToolsView }
        }
        override func layout() {
            super.layout()
            layoutEngineView()
        }
        override func resizeSubviews(withOldSize oldSize: NSSize) {
            layoutEngineView()
        }
        func layoutEngineView() {
            guard !bounds.isEmpty, let view = engineView else { return }
            guard let devToolsView, let page,
                let frames = CrestChromiumRoot.engineHost?.layoutDevTools(page: page.id, container: bounds),
                let frontendFrame = frames["devTools"]?.rectValue,
                let pageFrame = frames["page"]?.rectValue
            else {
                view.isHidden = false
                view.frame = bounds
                // A navigation can replace Chromium's renderer after this container
                // was laid out. Propagate the viewport even when its size is unchanged.
                view.setFrameSize(bounds.size)
                return
            }
            devToolsView.frame = frontendFrame
            devToolsView.setFrameSize(frontendFrame.size)
            // An empty page rectangle is the frontend asking to cover the page —
            // its own device-toolbar and drawer layouts do this — so the page is
            // hidden rather than squeezed to nothing.
            view.isHidden = pageFrame.isEmpty
            guard !pageFrame.isEmpty else { return }
            view.frame = pageFrame
            view.setFrameSize(pageFrame.size)
        }
        override var acceptsFirstResponder: Bool { true }
        override func becomeFirstResponder() -> Bool {
            // The page, never the docked inspector beside it: focus arriving at the
            // card belongs to the page the card is showing.
            guard let view = engineView else { return super.becomeFirstResponder() }
            return window?.makeFirstResponder(view) ?? false
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { page?.attachIfPossible() } else { page?.detach() }
        }
        func didAttach(to host: BrowserWebHostView) { page?.attachIfPossible() }
        func willDetach(from host: BrowserWebHostView) { page?.detach() }
        func presentationGeometryDidChange() { layoutEngineView() }
    }
    extension ChromiumNativePage: BrowserPageContentScripting {
        func install(_ script: BrowserContentScript, receive: @escaping @MainActor (BrowserContentMessage) -> Void)
            -> Bool
        {
            guard !disposed else { return false }
            contentScripts.append(script)
            contentReceivers[script.handlerName] = receive
            if created, let host {
                return host.addContentScript(script.source, page: id, mainFrameOnly: script.mainFrameOnly)
            }
            return true
        }

        func callAsyncJavaScriptInMainFrame(_ body: String) async -> Any? {
            guard created, !disposed, let host else { return nil }
            let result: String? = await withCheckedContinuation { continuation in
                host.evaluateContentScript(body, page: id, frame: "main") { json in continuation.resume(returning: json)
                }
            }
            guard let data = result?.data(using: .utf8),
                let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
                !(value is NSNull)
            else { return nil }
            return value
        }

        func callAsyncJavaScript(_ body: String, arguments: [String: Any], in frame: BrowserContentFrame) async throws
            -> Any?
        {
            guard created, !disposed, let host, let frameID = frame.handle as? String else { return nil }
            // The arguments arrive as constants named for their keys, as WebKit's
            // callAsyncJavaScript binds them.
            var source = ""
            if !arguments.isEmpty {
                let json = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
                source = "const __crestArguments = \(json);\n"
                for key in arguments.keys.sorted() { source += "const \(key) = __crestArguments[\"\(key)\"];\n" }
            }
            source += body
            let result: String? = await withCheckedContinuation { continuation in
                host.evaluateContentScript(source, page: id, frame: frameID) { json in
                    continuation.resume(returning: json)
                }
            }
            guard let data = result?.data(using: .utf8),
                let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
                !(value is NSNull)
            else { return nil }
            return value
        }
    }
    extension ChromiumNativePage: BrowserMediaSessionTransport {
        func activateMediaSession(documentIdentifier: String) {
            guard created, !disposed else { return }
            _ = host?.command(ChromiumPageHostCommand.mediaActivate.rawValue, page: id, url: documentIdentifier)
        }

        func performMediaSessionAction(_ action: BrowserMediaSessionAction, documentIdentifier: String) {
            guard created, !disposed else { return }
            _ = host?.command(
                ChromiumPageHostCommand.mediaAction.rawValue, page: id, url: "\(action.rawValue):\(documentIdentifier)")
        }

        func setMediaSessionMuted(_ muted: Bool, documentIdentifier: String) {
            guard created, !disposed else { return }
            _ = host?.command(
                ChromiumPageHostCommand.mediaMute.rawValue, page: id, url: "\(muted ? 1 : 0):\(documentIdentifier)")
        }
    }

    private enum ChromiumPageHostCommand: String, Codable, Sendable {
        case inspect = "engine.inspect"
        case inspectVisible = "engine.inspect_visible"
        case inspectClose = "engine.inspect_close"
        case inspectConsole = "engine.inspect_console"
        case inspectElements = "engine.inspect_elements"
        case inspectNetwork = "engine.inspect_network"
        case pictureInPictureEnter = "engine.picture_in_picture_enter"
        case history = "engine.history"
        case reload = "engine.reload"
        case reloadFromOrigin = "engine.reload_from_origin"
        case stop = "engine.stop"
        case infoBar = "engine.infobar"
        case faviconRefresh = "engine.favicon_refresh"
        case showBlockedPopups = "engine.show_blocked_popups"
        case storeState = "engine.store_state"
        case zoom = "engine.zoom"
        /// A standalone page's load. TRANSITIONAL until such pages open through
        /// the core.
        case navigate = "engine.navigate"
        case mediaActivate = "engine.media_activate"
        case mediaAction = "engine.media_action"
        case mediaMute = "engine.media_mute"
    }

    extension BrowserEnginePermissionResponse {
        /// The host's reply code for a permission request.
        fileprivate var hostCode: Int {
            switch self {
            case .allow: 1
            case .allowOnce: 2
            case .block: 3
            case .dismiss: 4
            }
        }
    }
#endif
