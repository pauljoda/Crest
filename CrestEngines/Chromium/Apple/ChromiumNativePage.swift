#if CREST_CHROMIUM_HOST
import AppKit
import Observation
import PDFKit

/// Owns the WebContents behind the original Crest page card. The shell and
/// portable session retain their tab identities; this object owns only a page.
@Observable @MainActor
final class ChromiumNativePage: BrowserPageEngine {
    let registration = BrowserEngineRegistration.chromium
    let id = UUID().uuidString
    let surface = ChromiumNativePageView()
    var isPrivateBrowsing = false
    private let profileID: UUID
    var observer: (String, [String: Any]) -> Void
    var linkHandler: (String, URL, String) -> Bool = { _, _, _ in false }
    var protectedLinkHandler: (URL) -> (() -> Void)? = { _ in nil }
    var modifiedLinkHandler: (URL, Int, String) -> (BrowserLinkNavigationDecision, (() -> Void)?) = { _, _, _ in (.navigate, nil) }
    private var host: (any CrestChromiumEngineHost)?
    private var requestedURL: URL?
    private var pendingInteractionState: Data?
    private var pendingNavigation: (token: String, url: URL)?
    private var zoom: CGFloat = 1
    private var creating = false
    private var created = false
    private var disposed = false

    /// The live pages the engine can name. A side-panel request arrives with
    /// only a page identifier, so the page it belongs to has to be reachable
    /// without a view context. The entries are weak: a page belongs to its
    /// window's pool and this lookup must not keep one alive.
    private final class Reference { weak var page: ChromiumNativePage? }
    private static var registry: [String: Reference] = [:]
    static func live(_ id: String) -> ChromiumNativePage? {
        guard let page = registry[id]?.page else { registry[id] = nil; return nil }
        return page.disposed ? nil : page
    }

    init(profileID: UUID, observer: @escaping (String, [String: Any]) -> Void = { _, _ in }) {
        self.profileID = profileID
        self.observer = observer
        surface.page = self
        let reference = Reference()
        reference.page = self
        Self.registry[id] = reference
    }

    var nativeView: NSView { surface }
    func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool {
        guard !created, !creating, !disposed, pendingNavigation == nil,
            navigation.implementation == registration.implementationId,
            UUID(uuidString: navigation.token) != nil else { return false }
        pendingNavigation = (navigation.token, url)
        return true
    }
    func discardNavigation(_ token: String) {
        (host ?? CrestChromiumRoot.engineHost)?.discardPendingNavigation(token)
    }
    func showInspector() -> Bool {
        guard created, !disposed, let host else { return false }
        return host.command("engine.inspect", page: id, url: nil)
    }
    func toggleInspector(_ panel: BrowserDeveloperPanel, current: BrowserDeveloperPanel?) -> BrowserWebInspectorToggleResult {
        guard created, !disposed, let host else { return .unavailable }
        let isOpen = host.command("engine.inspect_visible", page: id, url: nil)
        if isOpen, current == panel {
            return host.command("engine.inspect_close", page: id, url: nil) ? .closed : .unavailable
        }
        let command: String
        switch panel {
        case .console: command = "engine.inspect_console"
        case .elements: command = "engine.inspect_elements"
        case .network: command = "engine.inspect_network"
        }
        guard host.command(command, page: id, url: nil) else { return .unavailable }
        // Chromium selects a starting panel for Console and Elements only. A
        // Network request opens DevTools wherever it was, so report no panel
        // rather than claiming a selection the engine did not make.
        return .opened(panel == .network ? nil : panel)
    }
    var interactionState: Data? {
        guard created, !disposed, let host, let state = host.interactionState(forPage: id) else { return nil }
        return BrowserEngineInteractionState(engine: "chromium", version: host.engineVersion(), payload: state).encoded()
    }

    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool {
        guard !disposed, let host = host ?? CrestChromiumRoot.engineHost,
            let payload = BrowserEngineInteractionState.payload(state, engine: "chromium", version: host.engineVersion()) else { return false }
        if created {
            return host.restorePage(id, interactionState: payload, expectedURL: ChromiumInternalURL.engine(url.absoluteString))
        }
        requestedURL = url
        pendingInteractionState = payload
        attachIfPossible()
        return true
    }
    private(set) var backHistory: [BrowserNavigationHistoryItem] = []
    private(set) var forwardHistory: [BrowserNavigationHistoryItem] = []
    func mediaActivity() async -> BrowserPageMediaActivity? {
        guard created, !disposed, let values = host?.mediaActivity(forPage: id) else { return nil }
        return BrowserPageMediaActivity(isPlaying: values["playing"] as? Bool == true,
            isCapturing: values["capturing"] as? Bool == true,
            hasPictureInPicture: values["pictureInPicture"] as? Bool == true)
    }
    func transferOwnership(to windowID: BrowserWindowID) -> Bool {
        guard created, !disposed, let host else { return false }
        return host.preparePage(id, forWindow: windowID.rawValue.uuidString)
    }

    func capture(rect: CGRect?, width: CGFloat?, completion: @escaping @MainActor (NSImage?) -> Void) {
        guard created, !disposed, let host else { completion(nil); return }
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
        _ = host?.command("engine.history", page: id, url: String(offset))
    }
    func reload(bypassingCache: Bool) {
        command(bypassingCache ? "engine.reload_from_origin" : "engine.reload")
    }
    func stop() { command("engine.stop") }

    func load(_ url: URL) {
        if let pendingNavigation, pendingNavigation.url != url {
            discardNavigation(pendingNavigation.token)
            self.pendingNavigation = nil
        }
        pendingInteractionState = nil
        requestedURL = url
        if created { navigatePendingURL() }
        else { attachIfPossible() }
    }

    func attachIfPossible() {
        guard !disposed, let windowID = surface.window?.identifier?.rawValue,
            let host = CrestChromiumRoot.engineHost else { return }
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
        guard !creating else { return }
        let sourceProfile = isPrivateBrowsing ? CrestChromiumRoot.privateSourceProfileID : nil
        guard !isPrivateBrowsing || sourceProfile != nil else { observer("creation_failed", [:]); return }
        creating = true
        if !host.createPage(id, profile: profileID.uuidString, window: windowID,
            privateMode: isPrivateBrowsing, sourceProfile: sourceProfile?.uuidString, observer: { [weak self] event, values in
                MainActor.assumeIsolated { self?.receive(event, values: values) }
            }) {
            creating = false
            observer("creation_failed", [:])
        }
    }

    func adopt(_ token: String) -> Bool {
        guard !created, !creating, !disposed, let host = CrestChromiumRoot.engineHost else { return false }
        self.host = host
        creating = true
        let accepted = host.adoptPage(token, asPage: id, profile: profileID.uuidString) { [weak self] event, values in
            MainActor.assumeIsolated { self?.receive(event, values: values) }
        }
        if !accepted { creating = false }
        return accepted
    }

    /// `configuration.wraps` is dropped: the host's find command takes no wrap
    /// argument and the engine's find always wraps. The registration declares
    /// that limitation rather than letting the caller assume otherwise.
    func performFind(_ query: String, configuration: BrowserFindConfiguration,
                     completion: @escaping @MainActor (Bool) -> Void) {
        guard created, !disposed, let host,
            host.find(inPage: id, query: query, backwards: configuration.backwards,
                caseSensitive: configuration.caseSensitive, completion: { found in
                    MainActor.assumeIsolated { completion(found) }
                }) else { completion(false); return }
    }

    // MARK: Content bridges

    private var contentScripts: [BrowserContentScript] = []
    private var contentReceivers: [String: @MainActor (BrowserContentMessage) -> Void] = [:]
    var contentScripting: (any BrowserPageContentScripting)? { self }

    private func receiveContentMessage(_ values: [String: Any]) {
        guard let handler = values["handler"] as? String, let receive = contentReceivers[handler],
            let body = (values["body"] as? String)?.data(using: .utf8)
                .flatMap({ try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }),
            let frame = values["frame"] as? String, let securityProtocol = values["protocol"] as? String,
            let host = values["host"] as? String
        else { return }
        receive(BrowserContentMessage(
            handlerName: handler, body: body,
            frame: BrowserContentFrame(
                isMainFrame: values["isMainFrame"] as? Bool == true, securityProtocol: securityProtocol,
                host: host, port: values["port"] as? Int ?? 0, handle: frame as NSString)))
    }

    struct SitePermission: Identifiable {
        let id: String
        let label: String
        var value: Int
        let supportsAsk: Bool
    }
    var permissions: [SitePermission] {
        (host?.permissions(forPage: id) ?? []).compactMap { item in
            guard let id = item["id"] as? String, let label = item["label"] as? String,
                let value = item["value"] as? Int else { return nil }
            return SitePermission(id: id, label: label, value: value, supportsAsk: item["supportsAsk"] as? Bool ?? false)
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
        return host.command("engine.infobar", page: id, url: "\(response):\(barID)")
    }

    /// Rebuilt from the chain the engine verified, so the system certificate
    /// sheet can show it. The trust carries an SSL policy for the page's host.
    var serverTrust: SecTrust? {
        guard created, !disposed, let host, let chain = host.certificateChain(forPage: id) as [NSData]?,
            !chain.isEmpty else { return nil }
        let certificates = chain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard certificates.count == chain.count else { return nil }
        var trust: SecTrust?
        let policy = SecPolicyCreateSSL(true, pageHost as CFString?)
        guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess else { return nil }
        return trust
    }
    private var pageHost: String?
    private(set) var mediaSessionLocation: String?
    var mediaSessionTransport: (any BrowserMediaSessionTransport)? { self }

    func showBlockedPopups() -> Bool {
        guard created, !disposed, let host else { return false }
        return host.command("engine.show_blocked_popups", page: id, url: nil)
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
            return ExtensionAction(id: id, name: name, badge: item["badge"] as? String ?? "", icon: item["icon"] as? NSImage, pinned: item["pinned"] as? Bool ?? false)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func runExtension(_ extensionID: String, anchor: BrowserExtensionPopupAnchor? = nil) {
        guard created, !disposed else { return }
        let anchor = anchor ?? BrowserExtensionPopupAnchor(screenPoint: NSEvent.mouseLocation, sourceWindow: surface.window)
        guard let source = anchor.presentationSource(fallbackWindow: surface.window) else { return }
        if host?.runExtension(extensionID, page: id, anchorView: source.view, anchorRect: source.rect) != true {
            CrestChromiumRoot.showNativeNotice("This extension action is unavailable on this page.", icon: "puzzlepiece.extension")
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
        observer("developer_panel", [:])
    }

    /// The Chrome Web Store listing this page is showing asked Crest to install
    /// or remove the extension it is about. The engine has already checked that
    /// the extension is the one the page's own URL names, and the destination is
    /// this page's own Space — a listing can never reach another Space or a
    /// private window, which keeps no persistent extension state.
    private func performStoreRequest(_ event: String, _ values: [String: Any]) {
        let store = CrestChromiumRoot.extensions
        guard !isPrivateBrowsing, let id = values["id"] as? String,
            let space = CrestChromiumRoot.extensionSpaces.first(where: { $0.profile.id == profileID })
        else { refreshStoreState(); return }
        let refresh: @MainActor () -> Void = { [weak self] in self?.refreshStoreState() }
        if event == "store_remove" {
            store.confirmRemoval(id, in: space, completion: refresh)
        } else {
            store.install(id, in: space, anchor: surface, completion: refresh)
        }
    }

    /// Restates the listing's install button from Chromium's own registry once
    /// an install review has finished, been canceled, or was never offered.
    private func refreshStoreState() {
        guard created, !disposed else { return }
        _ = host?.command("engine.store_state", page: id, url: nil)
    }

    static func webStoreExtensionID(_ url: URL?) -> String? {
        guard let url, url.scheme == "https", url.host == "chromewebstore.google.com",
            url.pathComponents.count >= 3, url.pathComponents[1] == "detail",
            let id = url.pathComponents.last, id.count == 32,
            id.allSatisfy({ ("a"..."p").contains(String($0)) }) else { return nil }
        return id
    }

    func setZoom(_ zoom: CGFloat) {
        self.zoom = zoom
        if created { _ = host?.command("engine.zoom", page: id, url: String(Double(zoom))) }
    }

    func detach() { if created { host?.didDetachPage(id) } }

    func command(_ command: String) {
        guard created, !disposed else { return }
        _ = host?.command(command, page: id, url: nil)
    }

    func dispose() {
        guard !disposed else { return }
        if let pendingNavigation { discardNavigation(pendingNavigation.token) }
        pendingNavigation = nil
        disposed = true
        Self.registry[id] = nil
        surface.devToolsView = nil
        surface.subviews.forEach { $0.removeFromSuperview() }
        host?.disposePages([id], windows: [], releaseProfiles: [])
        host = nil
    }

    private func navigatePendingURL() {
        guard let requestedURL else { return }
        self.requestedURL = nil
        if let navigation = pendingNavigation {
            pendingNavigation = nil
            pendingInteractionState = nil
            if host?.loadPendingNavigation(navigation.token, page: id,
                expectedURL: ChromiumInternalURL.engine(requestedURL.absoluteString)) != true {
                // A stale request must not be retried as a bare URL, which loses
                // the initiating frame's security and referrer information.
                observer("changed", ["url": requestedURL.absoluteString, "isLoading": false,
                    "failure": String(localized: "This link is no longer available. Open it again from its original page.")])
            }
            return
        }
        let state = pendingInteractionState
        pendingInteractionState = nil
        if let state, host?.restorePage(id, interactionState: state,
            expectedURL: ChromiumInternalURL.engine(requestedURL.absoluteString)) == true { return }
        _ = host?.command("engine.navigate", page: id, url: ChromiumInternalURL.engine(requestedURL.absoluteString))
    }

    private func history(_ value: Any?) -> [BrowserNavigationHistoryItem] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let depth = item["depth"] as? Int, depth > 0,
                let rawURL = item["url"] as? String,
                let url = URL(string: ChromiumInternalURL.presented(rawURL)) else { return nil }
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return BrowserNavigationHistoryItem(depth: depth,
                title: title.isEmpty ? url.host() ?? url.absoluteString : title, url: url)
        }
    }

    private func receive(_ event: String, values: [String: Any]) {
        guard !disposed else { return }
        if event == "content_message" {
            receiveContentMessage(values)
            return
        }
        if event == "changed" {
            backHistory = history(values["backHistory"])
            forwardHistory = history(values["forwardHistory"])
            if values["committed"] as? Bool == true { surface.layoutEngineView() }
            pageHost = (values["url"] as? String).flatMap(URL.init(string:))?.host()
            mediaSessionLocation = values["url"] as? String
        }
        if event == "created" {
            created = true
            creating = false
            for script in contentScripts {
                _ = host?.addContentScript(script.source, page: id, mainFrameOnly: script.mainFrameOnly)
            }
            host?.setLinkHandler(page: id) { [weak self] action, address, label in
                MainActor.assumeIsolated {
                    guard let self, !self.disposed, let url = URL(string: address) else { return false }
                    return self.linkHandler(action, url, label)
                }
            }
            host?.setProtectedLinkHandler(page: id) { [weak self] address in
                var deferred: CrestDeferredNavigation?
                MainActor.assumeIsolated {
                    guard let self, !self.disposed, let url = URL(string: address),
                        let action = self.protectedLinkHandler(url) else { return }
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
                        reply("navigate", nil)
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
                    reply(decision.rawValue, deferred)
                }
            }
            attachIfPossible()
            setZoom(zoom)
            navigatePendingURL()
        } else if event == "creation_failed" {
            creating = false
        } else if event == "store_install" || event == "store_remove" {
            performStoreRequest(event, values)
        }
        observer(event, ChromiumInternalURL.presentedValues(values))
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
            let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else {
            throw BrowserPageExportError.renderingFailed("The page could not be prepared for printing.")
        }
        return operation
    }

    private func exportData(format: String, width: CGFloat = 0) async throws -> Data {
        guard created, !disposed, let host else { throw BrowserPageExportError.pageUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            host.exportPage(id, format: format, width: width) { data, error in
                MainActor.assumeIsolated {
                    if let data { continuation.resume(returning: data) }
                    else {
                        continuation.resume(throwing: BrowserPageExportError.renderingFailed(
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
    func install(_ script: BrowserContentScript, receive: @escaping @MainActor (BrowserContentMessage) -> Void) -> Bool {
        guard !disposed else { return false }
        contentScripts.append(script)
        contentReceivers[script.handlerName] = receive
        if created, let host { return host.addContentScript(script.source, page: id, mainFrameOnly: script.mainFrameOnly) }
        return true
    }

    func callAsyncJavaScript(_ body: String, arguments: [String: Any], in frame: BrowserContentFrame) async throws -> Any? {
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
            !(value is NSNull) else { return nil }
        return value
    }
}
extension ChromiumNativePage: BrowserMediaSessionTransport {
    func activateMediaSession(documentIdentifier: String) {
        guard created, !disposed else { return }
        _ = host?.command("engine.media_activate", page: id, url: documentIdentifier)
    }

    func performMediaSessionAction(_ action: BrowserMediaSessionAction, documentIdentifier: String) {
        guard created, !disposed else { return }
        _ = host?.command("engine.media_action", page: id, url: "\(action.rawValue):\(documentIdentifier)")
    }

    func setMediaSessionMuted(_ muted: Bool, documentIdentifier: String) {
        guard created, !disposed else { return }
        _ = host?.command("engine.media_mute", page: id, url: "\(muted ? 1 : 0):\(documentIdentifier)")
    }
}
#endif
