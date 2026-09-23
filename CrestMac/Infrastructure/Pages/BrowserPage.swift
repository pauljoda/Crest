import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import os

@Observable
@MainActor
final class BrowserPage: NSObject, BrowserMediaSessionCommandEndpoint, BrowserPagePermissionProviding {
    // MARK: - Variables

    var opensModifiedLinksInForeground = false
    @ObservationIgnored static let lifecycleSignposter = OSSignposter(
        subsystem: "com.pauldavis.crest",
        category: "WebKitLifecycle"
    )

    /// The engine's per-page adapter. Everything the page asks of its engine
    /// goes through it or through `pageEngine`.
    @ObservationIgnored let engineAdapter: any BrowserPageEngineAdapter
    @ObservationIgnored let pageEngine: any BrowserPageEngine
    var pictureInPicture: (any BrowserPagePictureInPictureController)? { engineAdapter.pictureInPicture }
    var linkHover: BrowserLinkHoverController? { engineAdapter.linkHover }
    var linkDrag: BrowserLinkDragController? { engineAdapter.linkDrag }
    @ObservationIgnored lazy var focusRestoration: BrowserWebFocusRestorationController = {
        let controller = BrowserWebFocusRestorationController(webView: nativeView)
        engineAdapter.install(controller)
        return controller
    }()

    private(set) var url: URL?
    private(set) var title = ""
    private(set) var estimatedProgress = 0.0
    private(set) var isLoading = false
    private(set) var isContentFullscreen = false
    private(set) var hasOnlySecureContent = false
    private(set) var faviconData: Data?
    private(set) var themeColor: NSColor?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    var processTerminationCount = 0
    var committedNavigationCount = 0
    var completedNavigationCount = 0
    private(set) var navigationFailure: BrowserNavigationFailure?
    var blockedPopupState = BrowserBlockedPopupPageState()
    private(set) var engineInfoBars: [BrowserEngineInfoBar] = []
    var pendingServerTrustIdentity: BrowserServerTrustIdentity?
    var pendingNavigationURL: URL?
    var webContentFailureMessage: String?
    var isFindPresented: Bool { findSession.isPresented }
    var findQuery: String { findSession.query }
    var findMatchState: BrowserFindMatchState { findSession.matchState }
    var findFocusRequest: Int { findSession.focusRequest }
    private(set) var pageZoom: CGFloat = BrowserPageZoomPolicy.defaultLevel
    let translation = BrowserPageTranslation()
    var readerModeState: BrowserReaderModeState { readerModeSession?.state ?? .unavailable }
    var isContentBlockingActive: Bool { engineAdapter.isContentBlockingActive }
    private(set) var developerPanel: BrowserDeveloperPanel?
    private(set) var isRegionCapturePresented = false
    private(set) var developerCaptureFeedback: String?
    private(set) var developerCaptureFeedbackRevision = 0
    var isCredentialAccessEnabled: Bool { credentialSession.isEnabled }
    var credentialFillRequest: BrowserCredentialFillRequest? { credentialState.fillRequest }
    var credentialSaveCandidate: BrowserCredentialSaveCandidate? { credentialState.saveCandidate }
    /// The pool that owns this page. Weak because the pool owns the page.
    @ObservationIgnored weak var host: (any BrowserPageHosting)?
    @ObservationIgnored var windowRouting: BrowserPageWindowRouting?

    /// True when web content opened this page through `window.open()`. It gates
    /// `window.close()`, which may only close what script itself opened.
    @ObservationIgnored private(set) var wasOpenedAsPopup = false

    /// True from adoption until WebKit starts the popup's own navigation. WebKit
    /// drives an adopted popup, so nothing else may load it in that window —
    /// loading it here is what breaks `window.opener` and `document.write`.
    @ObservationIgnored var isAwaitingPopupNavigation = false

    @ObservationIgnored private var defaultPageZoom: CGFloat
    @ObservationIgnored private var hasTemporaryPageZoomOverride = false
    @ObservationIgnored var viewportFitOwner: UUID?
    @ObservationIgnored var viewportFitGeneration = 0

    @ObservationIgnored let dialogPresenter: BrowserDialogPresenter
    @ObservationIgnored let fileUploadAccess = BrowserFileUploadAccess()
    @ObservationIgnored var downloadCenter: BrowserDownloadCenter
    let sitePermissionRequests = BrowserPagePermissionController()
    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored let hostedNotificationCenter: (any BrowserHostedWebNotificationCentering)?
    @ObservationIgnored let recoverNotificationSystemAuthorization: @MainActor () async -> Void
    @ObservationIgnored let serverTrustOverrides: BrowserServerTrustOverrideStore
    @ObservationIgnored let spaceID: SpaceID
    @ObservationIgnored let profileID: UUID
    @ObservationIgnored let spaceName: String
    @ObservationIgnored let navigationDecider: BrowserNavigationDecider
    @ObservationIgnored let popupCoordinator: BrowserPopupCoordinator
    @ObservationIgnored let externalSchemeCoordinator: BrowserExternalSchemeCoordinator
    /// The URL Crest asked this page to load, as opposed to one web content
    /// asked for. Only an app-initiated load may reach a `file:` URL.
    @ObservationIgnored var appInitiatedURL: URL?
    @ObservationIgnored let openModifiedLink: (URLRequest, SpaceID, Bool) -> Void
    @ObservationIgnored let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored let handleLinkDrag: (BrowserPeekInteractionEvent) -> Void
    @ObservationIgnored var navigationContext: BrowserPageNavigationContext?
    @ObservationIgnored var processRecovery = BrowserProcessRecovery()
    @ObservationIgnored private let findSession = BrowserFindSession()
    var readerModeSession: BrowserReaderModeSession? { engineAdapter.readerModeSession }
    var faviconSession: BrowserFaviconSession? { engineAdapter.faviconSession }
    @ObservationIgnored var sharingPicker: NSSharingServicePicker?
    @ObservationIgnored private var printOperation: NSPrintOperation?
    @ObservationIgnored private var preparingPrint = false
    /// The link the pending web-content context menu is over. Read and cleared
    /// by this page's `BrowserDesktopWebViewMenuHost` conformance.
    @ObservationIgnored var linkContextCapture = BrowserLinkContextCapturePolicy()
    @ObservationIgnored var downloadSourceStore = BrowserDownloadSourceStore()
    @ObservationIgnored var splitLinkHost: BrowserSplitLinkHost
    @ObservationIgnored var linkDestinationHost: BrowserLinkDestinationHost
    @ObservationIgnored var mediaSessionCoordinator: BrowserMediaSessionPageCoordinator?
    @ObservationIgnored var hostedNotificationIdentifiers: Set<String> = []
    @ObservationIgnored var hostedNotificationDocumentIdentifier = UUID().uuidString
    @ObservationIgnored private var userActivityHandler: (() -> Void)?
    @ObservationIgnored let credentialSession: BrowserCredentialSession
    var credentialState: BrowserCredentialPageState<BrowserCredentialSession.FillTarget> {
        credentialSession.state
    }
    @ObservationIgnored let httpAuthenticationSession: BrowserHTTPAuthenticationSession
    var displayURL: URL? {
        navigationFailure?.failingURL ?? pendingNavigationURL ?? url
    }

    // Session-only presentation state belongs to the live page, including in splits.
    private var developerToolbarVisibilityOverride: Bool?
    var developerViewport: BrowserDeveloperViewport? {
        didSet { pageEngine.setZoom(renderedPageZoom) }
    }

    var renderedPageZoom: CGFloat { developerViewport == nil ? pageZoom : 1 }

    var isDeveloperModeEnabled: Bool {
        developerToolbarVisibilityOverride
            ?? (developerViewport != nil || BrowserDeveloperModePolicy.isAutomatic(for: displayURL))
    }

    /// The tab that owns this page's Media Session, read when the session
    /// reports rather than captured when it is built.
    var mediaSessionOwner: @MainActor () -> BrowserTabRuntimeAssignment? {
        { [weak self] in
            self?.navigationContext.map {
                BrowserTabRuntimeAssignment(
                    tabID: $0.tabID, spaceID: $0.spaceID, profileID: $0.spaceAssignment.profileID)
            }
        }
    }

    var mediaSessionFallbackTitle: @MainActor () -> String? {
        { [weak self] in
            guard let self else { return nil }
            return self.navigationContext?.mediaSessionOwnerTitle(observedPageTitle: self.title)
                ?? BrowserTab.resolvedCustomTitle(self.title)
        }
    }

    var siteThemeIconAccent: BrowserTabIconAccent? {
        guard let color = themeColor?.usingColorSpace(.sRGB), color.alphaComponent > 0 else {
            return nil
        }
        return BrowserTabIconAccent(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
    }

    // MARK: - Initializers

    init(
        engine engineAdapter: any BrowserPageEngineAdapter,
        dialogPresenter: BrowserDialogPresenter,
        downloadCenter: BrowserDownloadCenter,
        permissionCenter: BrowserSitePermissionCenter,
        hostedNotificationCenter:
            (any BrowserHostedWebNotificationCentering)? = nil,
        recoverNotificationSystemAuthorization:
            (@MainActor () async -> Void)? = nil,
        serverTrustOverrides: BrowserServerTrustOverrideStore = BrowserServerTrustOverrideStore(),
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        spaceID: SpaceID,
        profileID: UUID,
        spaceName: String,
        allowsCredentialAccess: Bool = true,
        isCredentialAccessEnabled: Bool = true,
        defaultPageZoom: CGFloat = BrowserPageZoomPolicy.defaultLevel,
        loadHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.LoadCredential = { _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.SaveCredential = { _ in },
        openNewTab: @escaping (URL) -> Void,
        openModifiedLink: @escaping (URLRequest, SpaceID, Bool) -> Void = { _, _, _ in },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        handleLinkDrag: @escaping (BrowserPeekInteractionEvent) -> Void = { _ in },
        splitLinkHost: BrowserSplitLinkHost = .unavailable,
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
        opensExternalURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        let pageInterval = Self.lifecycleSignposter.beginInterval("Initialize Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Initialize Browser Page", pageInterval)
        }

        self.dialogPresenter = dialogPresenter
        self.downloadCenter = downloadCenter
        self.permissionCenter = permissionCenter
        self.hostedNotificationCenter = hostedNotificationCenter
        self.recoverNotificationSystemAuthorization =
            recoverNotificationSystemAuthorization
            ?? {
                await dialogPresenter
                    .recoverNotificationSystemAuthorization()
            }
        self.serverTrustOverrides = serverTrustOverrides
        self.spaceID = spaceID
        self.profileID = profileID
        self.spaceName = spaceName
        self.engineAdapter = engineAdapter
        pageEngine = engineAdapter.engine
        let normalizedDefaultPageZoom = BrowserPageZoomPolicy.normalizedDefault(
            defaultPageZoom
        )
        self.defaultPageZoom = normalizedDefaultPageZoom
        pageZoom = normalizedDefaultPageZoom
        self.openModifiedLink = openModifiedLink
        self.openPeek = openPeek
        self.handleLinkDrag = handleLinkDrag
        self.splitLinkHost = splitLinkHost
        self.linkDestinationHost = linkDestinationHost
        let httpAuthenticationSession = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            allowsCredentialSaving: allowsCredentialAccess
                && isCredentialAccessEnabled,
            loadCredential: loadHTTPAuthenticationCredential,
            saveCredential: saveHTTPAuthenticationCredential
        )
        self.httpAuthenticationSession = httpAuthenticationSession
        credentialSession = BrowserCredentialSession(
            spaceID: spaceID,
            supportsAccess: allowsCredentialAccess,
            isEnabled: isCredentialAccessEnabled,
            httpAuthentication: httpAuthenticationSession
        )
        navigationDecider = BrowserNavigationDecider()
        // Built before the popup coordinator so a popup whose destination belongs
        // to another application can be routed into the same consent path an
        // ordinary external-scheme navigation takes.
        let externalSchemeCoordinator = BrowserExternalSchemeCoordinator(
            spaceID: spaceID,
            spaceName: spaceName,
            permissionCenter: permissionCenter,
            prompt: { origin, destinationURL, requestedSpaceName in
                await dialogPresenter.presentExternalApplicationPermission(
                    origin: origin,
                    destinationURL: destinationURL,
                    spaceName: requestedSpaceName
                )
            },
            opensExternalURL: opensExternalURL
        )
        self.externalSchemeCoordinator = externalSchemeCoordinator
        popupCoordinator = BrowserPopupCoordinator(
            openNewTab: openNewTab,
            handOffExternalScheme: { destinationURL, trigger, origin in
                externalSchemeCoordinator.handOff(
                    destinationURL: destinationURL,
                    trigger: trigger,
                    origin: origin
                )
            }
        )
        super.init()
        // The Space's default zoom; an engine that creates its page later
        // replays it then.
        pageEngine.setZoom(pageZoom)
        engineAdapter.attach(to: self, allowsCredentialAccess: allowsCredentialAccess)
        if let mediaSessionStore {
            mediaSessionCoordinator =
                pageEngine.mediaSessionTransport.map {
                    BrowserMediaSessionPageCoordinator(
                        transport: $0, endpoint: self, store: mediaSessionStore,
                        owner: mediaSessionOwner, fallbackTitle: mediaSessionFallbackTitle)
                } ?? engineAdapter.makeMediaSessionCoordinator(for: self, store: mediaSessionStore)
        }
        // An engine that runs Crest's content bridges itself receives them here;
        // the WebKit adapter installs its own through its user content controller.
        if allowsCredentialAccess, let scripting = pageEngine.contentScripting {
            _ = scripting.install(
                BrowserContentScript(
                    source: BrowserCredentialContentBridge.source,
                    handlerName: BrowserCredentialContentBridge.messageHandlerName,
                    mainFrameOnly: false
                )
            ) { [weak self] message in
                guard let self else { return }
                self.credentialSession.receive(message.body, from: message.frame, topLevelURL: self.url)
            }
        }
    }

    // MARK: - Actions - Navigation

    /// Records that web content opened this page and that WebKit still owes it a
    /// navigation. Only a page pool adopting a popup calls this.
    func markOpenedAsPopup() {
        wasOpenedAsPopup = true
        isAwaitingPopupNavigation = true
    }

    func load(_ url: URL) {
        load(URLRequest(url: url))
    }

    func load(_ request: URLRequest) {
        // An engine that reports its own navigations prepares the page when it
        // says one started; until then the page only shows the load pending.
        if pageEngine.reportsNavigationState, let destination = request.url {
            pendingNavigationURL = destination
            webContentFailureMessage = nil
            isLoading = true
            pageEngine.load(request)
            return
        }
        appInitiatedURL = request.url
        prepareForNavigation(to: request.url)
        pageEngine.load(request)
    }

    /// Replays a request WebKit classified as web-content navigation in this
    /// page without granting it the broader trust of an app-initiated load.
    func loadWebContentRequest(_ request: URLRequest) {
        if pageEngine.reportsNavigationState { load(request); return }
        prepareForNavigation(to: request.url)
        pageEngine.load(request)
    }

    /// The adapter's tagged, opaque history. Uncommitted pages return nil so
    /// an empty renderer cannot overwrite a useful archive.
    var interactionState: Data? {
        guard pageEngine.registration.supports(.interactionState) else { return nil }
        return pageEngine.interactionState
    }

    /// Lets the adapter restore its own history instead of starting `url` afresh.
    /// Rejected state falls back to an ordinary load; an adapter that queues page
    /// creation also owns that fallback if restoration fails after attachment.
    @discardableResult
    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool {
        // WebKit owns an adopted popup's first navigation, and an adopted popup
        // has no archived state of its own to restore in the first place.
        guard pageEngine.registration.supports(.interactionState),
            !isAwaitingPopupNavigation, !wasOpenedAsPopup
        else { return false }
        appInitiatedURL = url
        prepareForNavigation(to: url)
        guard pageEngine.restoreInteractionState(state, expecting: url) else {
            pendingNavigationURL = nil
            return false
        }
        return true
    }

    func monitorUserActivity(_ handler: @escaping () -> Void) {
        userActivityHandler = handler
        engineAdapter.monitorUserActivity(for: self)
    }

    func styleVisitedLinks(history: [BrowserHistoryEntry]) async {
        await engineAdapter.styleVisitedLinks(history: history)
    }

    func stopMonitoringUserActivity() {
        userActivityHandler = nil
    }

    func updateNavigationContext(
        tab: BrowserTab,
        automaticallyOpensPeek: Bool = true
    ) {
        let previousTitle = navigationContext?.title
        let shouldRefreshAutomaticIcon =
            tab.iconMode == .automatic
            && !tab.hasCurrentAutomaticFavicon
            && url != nil
            && !isLoading
        if faviconData != tab.displayFaviconData
            || navigationContext?.iconMode != tab.iconMode
            || navigationContext?.tabID != tab.id
        {
            faviconSession?.invalidate()
            faviconData = tab.displayFaviconData
        }
        navigationContext = BrowserPageNavigationContext(
            tab: tab,
            spaceID: spaceID,
            profileID: profileID,
            automaticallyOpensPeek: automaticallyOpensPeek
        )
        linkDrag?.contextDidChange()
        if previousTitle != navigationContext?.title {
            mediaSessionCoordinator?.ownerTitleDidChange()
        }
        if shouldRefreshAutomaticIcon {
            refreshFavicon()
        }
    }

    func prepareForSpaceDeletion() {
        faviconSession?.stop()
        sitePermissionRequests.setPresentationAvailable(false)
        translation.reset()
        readerModeSession?.invalidate()
        linkHover?.detach()
        linkDrag?.detach()
        focusRestoration.invalidate()
        mediaSessionCoordinator?.prepareForRemoval()
        pictureInPicture?.invalidate()
        fileUploadAccess.invalidate()
        userActivityHandler = nil
        linkContextCapture.clear()
        engineAdapter.detach(from: self)
        mediaSessionCoordinator = nil
    }

    func retryAfterProcessFailure() {
        processRecovery.reset()
        webContentFailureMessage = nil
        pageEngine.reload(bypassingCache: false)
    }

    // MARK: - Actions - Find and developer tools

    func setDeveloperToolbarVisible(_ visible: Bool) {
        developerToolbarVisibilityOverride = visible
        if !visible { developerViewport = nil }
    }

    func presentFind() {
        findSession.present(hasLoadedPage: url != nil)
    }

    @discardableResult
    func showWebInspector() -> Bool {
        pageEngine.showInspector()
    }

    func toggleDeveloperPanel(_ panel: BrowserDeveloperPanel) {
        let result = pageEngine.toggleInspector(panel, current: developerPanel)
        switch result {
        case .opened(let openedPanel):
            developerPanel = openedPanel
        case .closed:
            developerPanel = nil
        case .unavailable:
            NSSound.beep()
        }
    }

    func beginRegionCapture() {
        guard url != nil else { return }
        isRegionCapturePresented = true
    }

    func cancelRegionCapture() {
        isRegionCapturePresented = false
    }

    func captureRegion(_ rect: CGRect) {
        guard isRegionCapturePresented else { return }
        isRegionCapturePresented = false
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = await withCheckedContinuation { continuation in
                    pageEngine.capture(rect: rect, width: nil) { continuation.resume(returning: $0) }
                }
                guard let image else { throw BrowserDeveloperCaptureError.pageUnavailable }
                guard Self.copyImageToPasteboard(image) else {
                    throw BrowserDeveloperCaptureError.encodingFailed
                }
                presentDeveloperCaptureFeedback("Capture Copied")
            } catch {
                presentDeveloperCaptureFeedback("Couldn’t Capture Page")
            }
        }
    }

    func copyFullPageCapture() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await fullPageSnapshot()
                guard Self.copyImageToPasteboard(image) else {
                    throw BrowserDeveloperCaptureError.encodingFailed
                }
                presentDeveloperCaptureFeedback("Full Page Capture Copied")
            } catch {
                presentDeveloperCaptureFeedback("Couldn’t Capture Full Page")
            }
        }
    }

    func savePortraitCapture() {
        Task { [weak self] in
            guard let self, let window = nativeView.window else { return }
            do {
                let snapshot = try await fullPageSnapshot(snapshotWidth: 720)
                let portrait = Self.portraitImage(from: snapshot)
                guard let data = Self.pngData(from: portrait) else {
                    throw BrowserDeveloperCaptureError.encodingFailed
                }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue =
                    BrowserDeveloperCapturePolicy
                    .pngFilename(title: title, url: url)
                panel.title = "Save Portrait Capture"
                panel.prompt = "Save"
                guard await panel.beginSheetModal(for: window) == .OK,
                    let destinationURL = panel.url
                else { return }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destinationURL, options: .atomic)
                }.value
                presentDeveloperCaptureFeedback("Portrait Capture Saved")
            } catch {
                presentDeveloperCaptureFeedback("Couldn’t Save Portrait Capture")
            }
        }
    }

    func dismissDeveloperCaptureFeedback() {
        developerCaptureFeedback = nil
    }

    private var findExecutor: any BrowserFindExecuting {
        pageEngine
    }

    func dismissFind() {
        findSession.dismiss(using: findExecutor)
    }

    func find(_ query: String, direction: BrowserFindDirection = .forward) {
        findSession.find(query, direction: direction, using: findExecutor)
    }

    // MARK: - Actions - Zoom

    @discardableResult
    func zoomIn() -> Bool {
        guard developerViewport == nil else { return false }
        return setTemporaryPageZoom(BrowserPageZoomPolicy.increased(from: pageZoom))
    }

    @discardableResult
    func zoomOut() -> Bool {
        guard developerViewport == nil else { return false }
        return setTemporaryPageZoom(BrowserPageZoomPolicy.decreased(from: pageZoom))
    }

    @discardableResult
    func resetZoom() -> Bool {
        guard developerViewport == nil else { return false }
        hasTemporaryPageZoomOverride = false
        return setPageZoom(defaultPageZoom)
    }

    /// Updates this page's global baseline without discarding a temporary zoom
    /// chosen through the page commands. A manually zoomed page rejoins the
    /// baseline when Reset is used, when recreation makes a new page, or when
    /// the newly selected default already equals its temporary value.
    @discardableResult
    func applyDefaultPageZoom(_ zoom: CGFloat) -> Bool {
        let normalized = BrowserPageZoomPolicy.normalizedDefault(zoom)
        defaultPageZoom = normalized
        if hasTemporaryPageZoomOverride {
            if BrowserPageZoomPolicy.levelsMatch(pageZoom, normalized) {
                hasTemporaryPageZoomOverride = false
            }
            return false
        }
        return setPageZoom(normalized)
    }

    // MARK: - Actions - Reader and info bars

    func refreshReaderModeAvailability() async {
        await readerModeSession?.refreshAvailability()
    }

    func setReaderModeActive(_ isActive: Bool) async throws {
        guard let readerModeSession else { throw BrowserReaderModeError.articleUnavailable }
        try await readerModeSession.setActive(isActive)
    }

    func toggleReaderMode() {
        readerModeSession?.toggle()
    }

    func respond(to bar: BrowserEngineInfoBar, with response: BrowserEngineInfoBar.Response) {
        // The engine withdraws the bar itself once it has taken the answer.
        if !pageEngine.respondToInfoBar(bar.id, response: response.rawValue) {
            engineInfoBars.removeAll { $0.id == bar.id }
        }
    }

    // MARK: - Actions - Credentials

    func dismissCredentialFillRequest() {
        credentialState.dismissFillRequest()
    }

    func setCredentialAccessEnabled(_ isEnabled: Bool) {
        credentialSession.setEnabled(isEnabled)
    }

    func dismissCredentialSaveCandidate() {
        credentialState.dismissSaveCandidate()
    }

    func fillCredential(_ credential: BrowserCredential, for requestID: UUID) async throws {
        guard let evaluate = credentialEvaluator else { throw CredentialVaultError.credentialManagerDisabled }
        try await credentialSession.fill(credential, for: requestID, evaluate: evaluate)
    }

    func fillGeneratedPassword(_ password: String, for requestID: UUID) async throws {
        guard let evaluate = credentialEvaluator else { throw CredentialVaultError.credentialManagerDisabled }
        try await credentialSession.fillGeneratedPassword(password, for: requestID, evaluate: evaluate)
    }

    /// Fills go back through the channel the credential bridge came in on.
    private var credentialEvaluator: BrowserCredentialSession.Evaluate? {
        guard let scripting = pageEngine.contentScripting else { return engineAdapter.credentialEvaluator }
        return { body, arguments, frame in
            try await scripting.callAsyncJavaScript(body, arguments: arguments, in: frame)
        }
    }

    // MARK: - Actions - Sharing and export

    @discardableResult
    func copyPageLink() -> Bool {
        BrowserPageLinkClipboard.copy(url)
    }

    func copyDeveloperPageLink() {
        if copyPageLink() {
            presentDeveloperCaptureFeedback("URL Copied")
        }
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        guard let url else { return false }
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? (url.host() ?? url.absoluteString) : label
        let escapedLabel =
            resolvedLabel
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("[\(escapedLabel)](\(url.absoluteString))", forType: .string)
        return true
    }

    private func fullPageSnapshot(snapshotWidth: CGFloat? = nil) async throws -> NSImage {
        guard url != nil, let service = pageEngine.documentServices else {
            throw BrowserDeveloperCaptureError.pageUnavailable
        }
        return try await service.fullPageSnapshot(width: snapshotWidth)
    }

    private static func copyImageToPasteboard(_ image: NSImage) -> Bool {
        guard let data = pngData(from: image) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }

    private static func pngData(from image: NSImage) -> Data? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard
            let cgImage = image.cgImage(
                forProposedRect: &proposedRect,
                context: nil,
                hints: nil
            )
        else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }

    private static func portraitImage(from snapshot: NSImage) -> NSImage {
        let horizontalInset: CGFloat = 64
        let verticalInset: CGFloat = 72
        let canvasSize = CGSize(
            width: snapshot.size.width + horizontalInset * 2,
            height: snapshot.size.height + verticalInset * 2
        )
        let imageRect = CGRect(
            x: horizontalInset,
            y: verticalInset,
            width: snapshot.size.width,
            height: snapshot.size.height
        )

        return NSImage(size: canvasSize, flipped: false) { canvasRect in
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.34, alpha: 1),
                NSColor(calibratedRed: 0.48, green: 0.25, blue: 0.52, alpha: 1),
                NSColor(calibratedRed: 0.14, green: 0.54, blue: 0.62, alpha: 1),
            ])
            gradient?.draw(in: canvasRect, angle: -35)

            let context = NSGraphicsContext.current
            context?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.38)
            shadow.shadowBlurRadius = 30
            shadow.shadowOffset = CGSize(width: 0, height: -14)
            shadow.set()
            NSColor.black.withAlphaComponent(0.18).setFill()
            NSBezierPath(
                roundedRect: imageRect.insetBy(dx: -2, dy: -2),
                xRadius: 14,
                yRadius: 14
            ).fill()
            context?.restoreGraphicsState()

            context?.saveGraphicsState()
            NSBezierPath(
                roundedRect: imageRect,
                xRadius: 12,
                yRadius: 12
            ).addClip()
            snapshot.draw(in: imageRect)
            context?.restoreGraphicsState()
            return true
        }
    }

    private func presentDeveloperCaptureFeedback(_ message: String) {
        developerCaptureFeedback = message
        developerCaptureFeedbackRevision &+= 1
    }

    func sharePage() {
        guard let url else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = self
        sharingPicker = picker
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, self.nativeView.window != nil, self.sharingPicker === picker else { return }
            let anchor = NSRect(
                x: self.nativeView.bounds.maxX - 1,
                y: self.nativeView.bounds.maxY - 1,
                width: 1,
                height: 1
            )
            picker.show(relativeTo: anchor, of: self.nativeView, preferredEdge: .minY)
        }
    }

    func printPage() {
        guard !preparingPrint, printOperation == nil, let service = pageEngine.documentServices,
            url != nil, let window = nativeView.window else { return }
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        let jobTitle = title.isEmpty ? url?.host() ?? ProductIdentity.name : title
        preparingPrint = true
        Task { [weak self, weak window] in
            guard let self else { return }
            defer { preparingPrint = false }
            guard let window else { return }
            do {
                let operation = try await service.printOperation(with: printInfo)
                guard nativeView.window === window, window.isVisible else { return }
                operation.jobTitle = jobTitle
                printOperation = operation
                operation.runModal(
                    for: window, delegate: self,
                    didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
            } catch {
                guard window.isVisible else { return }
                Self.postFailureNotice("The page couldn’t be printed.", error: error)
            }
        }
    }

    func pdfData() async throws -> Data {
        guard url != nil, let service = pageEngine.documentServices else { throw BrowserPageExportError.pageUnavailable }
        return try await service.pdfData()
    }

    func exportPDF() {
        guard let window = nativeView.window, url != nil else { return }
        let suggestedFilename = BrowserPageExportPolicy.pdfFilename(title: title, url: url)
        Task { [weak self, weak window] in
            guard let self, let window else { return }
            do {
                let data = try await pdfData()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = suggestedFilename
                panel.title = "Export Page as PDF"
                panel.prompt = "Export"
                guard await panel.beginSheetModal(for: window) == .OK,
                    let destinationURL = panel.url
                else { return }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destinationURL, options: .atomic)
                }.value
            } catch {
                presentPDFExportError(error, in: window)
            }
        }
    }

    func webArchiveData() async throws -> Data {
        guard url != nil, let service = pageEngine.documentServices else { throw BrowserPageExportError.pageUnavailable }
        return try await service.webArchiveData()
    }

    func exportWebArchive() {
        guard let window = nativeView.window, url != nil,
            let service = pageEngine.documentServices else { return }
        let format = service.archiveFormat
        let suggestedFilename = BrowserPageExportPolicy.webArchiveFilename(
            title: title,
            url: url,
            format: format
        )
        Task { [weak self, weak window] in
            guard let self, let window else { return }
            do {
                let data = try await webArchiveData()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .data]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = suggestedFilename
                panel.title = "Save Page as Web Archive"
                panel.prompt = "Save"
                guard await panel.beginSheetModal(for: window) == .OK,
                    let destinationURL = panel.url
                else { return }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destinationURL, options: .atomic)
                }.value
            } catch {
                presentWebArchiveExportError(error, in: window)
            }
        }
    }

    @objc private func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        if printOperation === operation {
            printOperation = nil
        }
    }

    // MARK: - Actions - Zoom state

    private func setTemporaryPageZoom(_ zoom: CGFloat) -> Bool {
        let changed = setPageZoom(zoom)
        hasTemporaryPageZoomOverride = !BrowserPageZoomPolicy.levelsMatch(
            pageZoom,
            defaultPageZoom
        )
        return changed
    }

    private func setPageZoom(_ zoom: CGFloat) -> Bool {
        guard zoom != pageZoom else {
            return false
        }
        pageZoom = zoom
        pageEngine.setZoom(renderedPageZoom)
        return true
    }

    // MARK: - Actions - Navigation state

    func prepareForNavigation(to url: URL?) {
        // Same-document navigation never commits a replacement document.
        // Cancel the current pull here; suspend new pulls only when WebKit
        // actually starts provisional navigation.
        linkDrag?.cancel()
        engineAdapter.prepareForNavigation()
        sitePermissionRequests.cancelAll()
        translation.reset()
        readerModeSession?.invalidate()
        pictureInPicture?.invalidate()
        linkHover?.beginNavigation()
        focusRestoration.invalidate()
        mediaSessionCoordinator?.prepareForNavigation()
        beginBlockedPopupNavigation()
        synchronizePopupPermission(for: url)
        faviconSession?.invalidate()
        pendingNavigationURL = url
        // A capture describes one document's DOM. A right-click whose menu
        // never opened — a page that cancelled the event to draw its own —
        // must not survive into the next document.
        linkContextCapture.clear()
        clearNavigationFailure(preservingPendingURL: true)
    }

    /// Shows a failed navigation in place of the page. `currentURL` is the
    /// engine's own document, the fallback when nothing was pending.
    func recordNavigationFailure(
        _ error: any Error,
        phase: BrowserNavigationFailurePhase,
        currentURL: URL?
    ) {
        let fallbackURL = pendingNavigationURL ?? currentURL ?? url
        pendingNavigationURL = nil
        navigationFailure = BrowserNavigationFailure(
            error: error,
            phase: phase,
            fallbackURL: fallbackURL
        )
        canGoBack = canReturnFromNavigationFailure || pageEngine.canGoBack
    }

    // MARK: - Actions - Engine observations

    func receive(_ event: BrowserPageEngineEvent) {
        switch event {
        case .navigationStarted:
            linkDrag?.beginNavigation()
            linkHover?.beginNavigation()
            credentialState.didStartNavigation()
            beginBlockedPopupNavigation()
            // A prompt the engine withdrew with its document has no one to answer.
            sitePermissionRequests.cancelAll()
            mediaSessionCoordinator?.prepareForNavigation()
        case .stateChanged(let state):
            receive(state)
        case .urlChanged(let value):
            translation.documentURLDidChange(from: url, to: value)
            url = value
            refreshNavigationState()
            credentialState.didChangeTopLevelURL(to: value)
        case .titleChanged(let value):
            recordObservedTitle(value)
            refreshNavigationState()
        case .progressChanged(let value):
            estimatedProgress = value
        case .loadingChanged(let value):
            isLoading = value
            refreshNavigationState()
        case .secureContentChanged(let value):
            hasOnlySecureContent = value
        case .themeColorChanged(let value):
            themeColor = value
        case .historyChanged:
            refreshNavigationState()
        case .infoBarAdded(let bar):
            guard !engineInfoBars.contains(where: { $0.id == bar.id }) else { return }
            engineInfoBars.append(bar)
        case .infoBarRemoved(let id):
            engineInfoBars.removeAll { $0.id == id }
        case .mediaSession(let body):
            mediaSessionCoordinator?.receive(body, isMainFrame: true)
        case .contentFullscreenChanged(let active):
            isContentFullscreen = active
        case .userActivity:
            userActivityHandler?()
        case .linkHovered(let destination):
            linkHover?.receiveEngineHover(destination)
        case .popupBlocked(let pageURL):
            recordEngineBlockedPopup(pageURL: pageURL, documentIdentifier: "\(committedNavigationCount)")
        case .favicon(let data, let source):
            if let source {
                guard let url, BrowserTabStateRestorePolicy.restoresArchivedState(archivedURL: source, tabURL: url)
                else { return }
            }
            faviconData = data
        case .developerPanelClosed:
            // The inspector went away on its own — its close button, an
            // undocked window close, or the engine tearing it down. Without
            // this the next Console command would try to close a panel that is
            // already gone instead of opening one.
            developerPanel = nil
        case .closeRequested:
            Task { @MainActor [weak self] in
                guard let self else { return }
                host?.closeWebContentInitiatedPage(self)
            }
        case .creationFailed(let message):
            isLoading = false
            webContentFailureMessage = message
        case .openRequested(let destination):
            openModifiedLink(URLRequest(url: destination), spaceID, true)
        }
    }

    private func receive(_ state: BrowserPageEngineState) {
        let wasLoading = isLoading
        // The engine creates a blank document before loading the requested URL.
        if state.url?.absoluteString == "about:blank", pendingNavigationURL != nil { return }
        url = state.url
        title = state.title
        isLoading = state.isLoading
        if !isLoading {
            linkDrag?.didFinishNavigation()
            // A navigation that failed or turned into a download ends
            // here without committing.
            linkHover?.didFailNavigation()
            mediaSessionCoordinator?.didFinishNavigation()
        }
        estimatedProgress = isLoading ? 0.5 : 1
        hasOnlySecureContent = state.hasOnlySecureContent
        themeColor = state.themeColor
        canGoBack = state.canGoBack
        canGoForward = state.canGoForward
        // A failure is reported once, by the navigation that failed; the
        // state changes after it do not repeat it. It stays until a
        // navigation commits: the engine retries a network error on its
        // own, and a retry that fails again commits no new error page.
        switch state.failure {
        case .processTerminated:
            webContentFailureMessage = "process_terminated"
            credentialState.webContentProcessDidTerminate()
            mediaSessionCoordinator?.webContentProcessDidTerminate()
        case .navigationFailed(let failure):
            pendingNavigationURL = nil
            navigationFailure = failure
            httpAuthenticationSession.authenticationFailed()
        case nil: break
        }
        if state.committed {
            isContentFullscreen = false
            pendingNavigationURL = nil
            navigationFailure = nil
            webContentFailureMessage = nil
            linkHover?.didCommitNavigation()
            mediaSessionCoordinator?.didCommitNavigation()
            committedNavigationCount += 1
            Task { await httpAuthenticationSession.authenticationSucceeded() }
            synchronizePopupPermission(for: state.url)
            synchronizeEngineSitePermissions(for: state.url)
        }
        if wasLoading, !isLoading, committedNavigationCount > 0 { completedNavigationCount += 1 }
    }

    // MARK: - Actions - Engine-enforced site permissions

    /// The permissions an engine enforces itself. Crest's per-Space record
    /// decides them and the engine is told the answer.
    static let engineEnforcedPermissions: [BrowserSitePermission] = [.camera, .microphone, .location, .notifications]

    /// Applies Crest's record for `url`'s site to an engine that enforces site
    /// permissions itself, so a revocation in Crest takes effect in the engine.
    func synchronizeEngineSitePermissions(for url: URL? = nil) {
        guard let origin = (url ?? displayURL).flatMap(BrowserSiteOrigin.init(url:)) else { return }
        for permission in Self.engineEnforcedPermissions {
            var decision = permissionCenter.decision(for: permission, origin: origin, in: spaceID)
            if decision == .ask, permission == .camera || permission == .microphone {
                decision = permissionCenter.decision(for: .cameraAndMicrophone, origin: origin, in: spaceID)
            }
            let allowed: Bool? = switch decision {
            case .grantPersistently, .grantForSession: true
            case .denyPersistently, .denyForSession: false
            case .ask: nil
            }
            _ = pageEngine.applySitePermission(permission, allowed: allowed)
        }
    }

    /// An engine's request for a permission Crest records: a saved decision
    /// answers at once, otherwise Crest's prompt asks and a lasting answer is
    /// saved for the Space. Replies use the host's codes: 1 allow, 2 allow this
    /// time, 3 block, 4 dismiss.
    func resolveEngineSitePermission(
        _ permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        topLevelOrigin: BrowserSiteOrigin
    ) async -> Int {
        switch permissionCenter.decision(for: permission, origin: origin, in: spaceID) {
        case .grantPersistently, .grantForSession: return 1
        case .denyPersistently, .denyForSession: return 3
        case .ask: break
        }
        let response = await sitePermissionRequests.response(
            to: permission, origin: origin, topLevelOrigin: topLevelOrigin, spaceName: spaceName)
        switch response {
        case .allowOnce: return 2
        case .denyOnce: return 4
        case .grantPersistently:
            permissionCenter.setDecision(.grantPersistently, for: permission, origin: origin, in: spaceID)
            return 1
        case .denyPersistently:
            permissionCenter.setDecision(.denyPersistently, for: permission, origin: origin, in: spaceID)
            return 3
        }
    }

    // MARK: - Actions - History availability

    func refreshNavigationState() {
        // An engine that reports its own navigation state already published it.
        guard !pageEngine.reportsNavigationState else { return }
        synchronizeNavigationHistory()
        canGoBack = canReturnFromNavigationFailure || !pageEngine.backHistory.isEmpty || pageEngine.canGoBack
        canGoForward = !pageEngine.forwardHistory.isEmpty || pageEngine.canGoForward
    }

    func clearNavigationFailure(preservingPendingURL: Bool = false) {
        navigationFailure = nil
        if !preservingPendingURL {
            pendingNavigationURL = nil
        }
        refreshNavigationState()
    }

    // MARK: - Actions - Failure notices

    private func presentPDFExportError(_ error: Error, in window: NSWindow) {
        Self.postFailureNotice("The page couldn’t be exported.", error: error)
    }

    private func presentWebArchiveExportError(_ error: Error, in window: NSWindow) {
        Self.postFailureNotice("The page couldn’t be saved as a web archive.", error: error)
    }

    /// A failed export or print needs nothing from the person, so it is a
    /// notice rather than an alert.
    private static func postFailureNotice(_ summary: String, error: Error) {
        BrowserNoticeCenter.shared.post(BrowserNotice(
            message: "\(summary) \(error.localizedDescription)",
            systemImage: "exclamationmark.triangle"))
    }

    // MARK: - Actions - Title and favicon

    private func recordObservedTitle(_ observedTitle: String?) {
        let normalizedTitle = observedTitle ?? ""
        guard title != normalizedTitle else { return }
        title = normalizedTitle
        mediaSessionCoordinator?.ownerTitleDidChange()
    }

    func refreshFavicon() {
        guard navigationContext?.iconMode == .automatic, url != nil else { return }
        if let faviconSession {
            faviconSession.refresh()
        } else {
            pageEngine.refreshFavicon()
        }
    }

    /// WebKit fetches the icon on demand; an engine that reports its own icon
    /// has already published it.
    func pullFavicon() async -> Data? {
        if let faviconSession { return await faviconSession.pull() }
        return faviconData
    }
}
