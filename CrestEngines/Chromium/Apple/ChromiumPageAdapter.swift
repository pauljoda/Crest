#if CREST_CHROMIUM_HOST
    import AppKit

    /// The desktop Chromium adapter for one page. The engine presents its page
    /// through `ChromiumNativePage` as the page's engine-neutral events; this
    /// connects them, the page's context menu rows and its link drags to the
    /// page.
    @MainActor
    final class ChromiumPageAdapter: BrowserPageEngineAdapter {
        // MARK: - Variables

        let native: ChromiumNativePage
        private weak var page: BrowserPage?
        var engine: any BrowserPageEngine { native }
        let enginePage: EnginePage

        /// The engine reports hovered links itself.
        private(set) lazy var linkHover: BrowserLinkHoverController? =
            BrowserLinkHoverController(contentView: native.nativeView)
        private(set) lazy var linkDrag: BrowserLinkDragController? = BrowserLinkDragController(
            nativeView: native.nativeView,
            context: { [weak self] in self?.page?.linkNavigationContext },
            dragsLinksToPeek: { [weak self] in self?.page?.corePage.linkPreferences?.dragsLinksToPeek == true },
            handle: { [weak self] event in self?.page?.handleLinkDrag(event) })
        let pictureInPicture: (any BrowserPagePictureInPictureController)?
        /// Reader Mode runs through the engine's content scripting, sharing the
        /// exact same core-owned script and session as WebKit.
        private(set) lazy var readerModeSession: BrowserReaderModeSession? = page.map {
            BrowserReaderModeSession(
                document: BrowserContentReaderModeDocument(
                    mainFrameOf: native,
                    url: { [weak self] in self?.native.currentURL },
                    translation: $0.translation))
        }
        // Chromium presents favicons and its error pages itself.
        var faviconSession: BrowserFaviconSession? { nil }
        /// The engine's request filter blocks for the document the page shows
        /// when the core says its Space blocks on that site.
        var isContentBlockingActive: Bool {
            guard let page, let url = page.live.documentURL, let origin = SiteOrigin(url: url),
                let core = page.host?.browser.core
            else { return false }
            return (try? core.query(ContentBlockingApplies(spaceID: page.spaceID, origin: origin))) == true
        }
        /// Chromium's binding reports the page's navigations to the core itself.
        var reporter: EnginePageReporter? { nil }
        /// Fills go through the engine's content scripting.
        var credentialEvaluator: BrowserCredentialSession.Evaluate? { nil }
        /// Translation runs through the engine's content scripting, in the
        /// page's main document.
        var translationDocument: BrowserTranslationDocument? { BrowserTranslationDocument(mainFrameOf: native) }

        // MARK: - Initializers

        init(_ native: ChromiumNativePage) {
            self.native = native
            enginePage = native.makeEnginePage()
            pictureInPicture = ChromiumPictureInPicturePageController(page: enginePage, scripting: native)
        }

        // MARK: - Actions - Lifecycle

        /// Chromium reports the page's Media Session and runs its commands
        /// itself.
        func makeMediaSessionCoordinator(
            for page: BrowserPage,
            store: BrowserMediaSessionStore
        ) -> BrowserMediaSessionPageCoordinator? {
            BrowserMediaSessionPageCoordinator(
                transport: native, endpoint: page, store: store,
                owner: page.mediaSessionOwner, fallbackTitle: page.mediaSessionFallbackTitle)
        }

        func attach(to page: BrowserPage, allowsCredentialAccess: Bool) {
            self.page = page
            native.profileID = page.profileID
            native.observer = { [weak page] event in page?.receive(event) }
            native.promptPresenter = page
            native.menuHost = page
            native.linkDrag = linkDrag
            linkDrag?.observeNativeMouseDown()
        }

        func detach(from page: BrowserPage) {
            pictureInPicture?.invalidate()
            enginePage.close()
            native.dispose()
        }

        func setPrivateBrowsing(_ isPrivate: Bool) { native.isPrivateBrowsing = isPrivate }

        // MARK: - Actions - Engine-owned services

        /// Chromium's page view takes focus through its own responder chain.
        func install(_ focusRestoration: BrowserWebFocusRestorationController) {}
        /// The engine presents a person's input as `PageInteracted`.
        func monitorUserActivity(for page: BrowserPage) {}
        /// Chromium styles visited links from its own history.
        func styleVisitedLinks(history: [HistoryEntryState]) async {}
        /// The engine enforces site permissions itself; the page's permission
        /// session has already carried the change to it.
        func sitePermissionDidChange(_ permission: SitePermission, on page: BrowserPage) {}
    }

    extension BrowserPage {
        /// The Chromium page behind this page, or nil when another engine hosts it.
        var chromiumPage: ChromiumNativePage? { (engineAdapter as? ChromiumPageAdapter)?.native }
    }

    /// Chromium's browser Media Session can ask the active video player to enter
    /// PiP without page JavaScript or a synthetic click. The floating surface is
    /// still Chromium-owned; this controller only follows Crest's tab lifecycle.
    @MainActor
    private final class ChromiumPictureInPicturePageController:
        BrowserPagePictureInPictureController, BrowserAutomaticPictureInPictureClient
    {
        // MARK: - Static Variables

        /// Child documents report their engine-issued handle only when they own
        /// video PiP. The probe also reaches shadow players whose entry event
        /// stays inside the shadow tree. No media state crosses frame origins.
        private static let frameScript = BrowserContentScript(
            source: #"""
                (() => {
                  const probe = 'crest-query-pip-owner';
                  let lastProbe = -Infinity;
                  const report = () => {
                    if (window !== top && document.pictureInPictureElement)
                      webkit.messageHandlers.crestPictureInPictureOwner.postMessage(true);
                  };
                  const children = () => {
                    if (performance.now() - lastProbe < 1000) return;
                    lastProbe = performance.now();
                    report();
                    for (let i = 0; i < window.frames.length; ++i)
                      window.frames[i].postMessage(probe, '*');
                  };
                  globalThis.__crestFindChildPiP = children;
                  if (window === top) return;
                  addEventListener('message', event => {
                    if (event.source !== parent || event.data !== probe) return;
                    children();
                  });
                  document.addEventListener('enterpictureinpicture', report, true);
                })();
                """#,
            handlerName: "crestPictureInPictureOwner", mainFrameOnly: false)

        private static let initialEntryCheckDelay: Duration = .milliseconds(600)
        private static let lateEntryCheckInterval: Duration = .milliseconds(100)
        private static let entryTimeout: Duration = .seconds(2)

        // MARK: - Variables

        private let page: EnginePage
        private let scripting: any BrowserPageContentScripting
        private var videoFrame: BrowserContentFrame?
        private let coordinator: BrowserAutomaticPictureInPictureCoordinator
        private var completion: (@MainActor (Bool) -> Void)?
        private var reconcileLateEntry: (@MainActor () -> Void)?
        private var check: Task<Void, Never>?

        var isPictureInPictureActive: Bool { page.mediaActivity.contains(.pictureInPicture) }
        var protectsPageResidency: Bool { isPictureInPictureActive || completion != nil }
        var canAutomaticallyEnterPictureInPicture: Bool {
            let activity = page.mediaActivity
            return activity.contains(.playing) && !activity.contains(.pictureInPicture)
        }

        // MARK: - Initializers

        init(
            page: EnginePage, scripting: any BrowserPageContentScripting,
            coordinator: BrowserAutomaticPictureInPictureCoordinator = .shared
        ) {
            self.page = page
            self.scripting = scripting
            self.coordinator = coordinator
            _ = scripting.install(Self.frameScript) { [weak self] message in
                guard !message.frame.isMainFrame else { return }
                self?.videoFrame = message.frame
            }
            coordinator.register(self)
        }

        // MARK: - Actions - Picture in Picture

        func timeline(moving seek: BrowserPictureInPictureTimeline.Seek?) async -> BrowserPictureInPictureTimeline? {
            if let videoFrame,
                let result = await BrowserPictureInPictureTimeline.read(
                    moving: seek,
                    evaluate: { body, arguments in
                        try await scripting.callAsyncJavaScript(body, arguments: arguments, in: videoFrame)
                    })
            {
                return result
            }
            return await BrowserPictureInPictureTimeline.read(moving: seek) { body, arguments in
                let probe = "if (!document.pictureInPictureElement) globalThis.__crestFindChildPiP?.();\n"
                return try await scripting.callAsyncJavaScriptInMainFrame(probe + body, arguments: arguments)
            }
        }

        func requestAutomaticEntry(for trigger: BrowserAutomaticPictureInPictureCoordinator.Trigger) {
            coordinator.request(from: self, for: trigger)
        }
        func returnToTab(reconcileLateEntry: @escaping @MainActor () -> Void) {
            // An entry already sent to Chromium's renderer cannot be withdrawn.
            if completion != nil { self.reconcileLateEntry = reconcileLateEntry }
        }

        func beginAutomaticPictureInPicture(completion: @escaping @MainActor (Bool) -> Void) {
            guard page.enterPictureInPicture() else {
                DiagnosticLog.pages.notice("Chromium page \(page.id) plays no video to float in Picture in Picture")
                completion(false)
                return
            }
            self.completion = completion
            check = Task { @MainActor [weak self] in
                // Keep the reservation and any redock request while the
                // renderer can still complete automatic entry.
                let clock = ContinuousClock()
                let deadline = clock.now + Self.entryTimeout
                var nextCheck = clock.now + Self.initialEntryCheckDelay
                while true {
                    do { try await clock.sleep(until: nextCheck) } catch { return }
                    guard let self else { return }
                    let entered = isPictureInPictureActive
                    if entered || clock.now >= deadline {
                        finishAutomaticEntry(entered)
                        return
                    }
                    nextCheck = min(clock.now + Self.lateEntryCheckInterval, deadline)
                }
            }
        }

        private func finishAutomaticEntry(_ entered: Bool) {
            DiagnosticLog.pages.notice("Chromium page \(page.id) floats in Picture in Picture: \(entered)")
            let reconcile = reconcileLateEntry
            reconcileLateEntry = nil
            let complete = completion
            completion = nil
            check = nil
            complete?(entered)
            if entered { reconcile?() }
        }

        func cancelAutomaticPictureInPicture() {
            check?.cancel()
            check = nil
            reconcileLateEntry = nil
            let complete = completion
            completion = nil
            complete?(false)
        }

        func invalidate() {
            coordinator.cancel(self)
        }
    }
#endif
