import AppKit
import Foundation
import WebKit
import XCTest

@testable import Crest

/// Live coverage for action popups whose startup depends on host `chrome.*`
/// calls made against the active tab.
///
/// Dark Reader's popup awaits a single `ui-bg-get-data` round trip. Its
/// background answers with `collect().then(sendResponse)` and no `.catch`,
/// while the popup's request carries no timeout and no `lastError` check. One
/// host call that stalls or throws on that path therefore strands the popup on
/// "Loading, please wait" forever, with no error surface. These tests pin the
/// popup lifecycle and time every host call it depends on, including on the
/// Chrome Web Store origin that Chrome protects and Crest does not.
@MainActor
final class BrowserExtensionActionPopupLiveTests: XCTestCase {
    private let darkReaderID = "eimadpbcbfnmbkopoojfekhnkhdbieeh"
    private let lastPassID = "hdokiejnpimakedhajhdlcegeplioahd"
    private let onePasswordID = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
    private let sponsorBlockID = "mnjggcdmjocbbbhaepdhchncahnbgone"

    /// Long enough for WebKit to evict a nonpersistent background that has
    /// nothing left to do.
    private static let backgroundEvictionIdleSeconds = 45

    func testLiveDarkReaderPopupCompletesOnEveryActiveTabAcrossRestoration()
        async throws
    {
        try skipUnlessLiveRunRequested()
        let candidate = try await candidate(
            extensionID: darkReaderID,
            slug: "dark-reader"
        )
        let storeURL = try XCTUnwrap(
            URL(string: "https://chromewebstore.google.com/")
        )
        let ordinaryURL = try XCTUnwrap(URL(string: "https://example.com/"))

        for activeTabURL in [ordinaryURL, storeURL] {
            for viaRestoration in [false, true] {
                let outcome = try await popupOutcome(
                    candidate: candidate,
                    extensionID: darkReaderID,
                    activeTabURL: activeTabURL,
                    viaRestoration: viaRestoration
                )
                let label =
                    "\(activeTabURL.absoluteString) "
                    + (viaRestoration ? "after restoration" : "after install")

                XCTAssertTrue(
                    outcome.presentsPopup,
                    "Dark Reader advertised no action popup for \(label)."
                )
                XCTAssertNotNil(
                    outcome.readyMilliseconds,
                    """
                    Dark Reader's popup never left "Loading, please wait" for \
                    \(label). Host calls: \(outcome.hostCalls). Runtime \
                    errors: \(outcome.contextErrors)
                    """
                )
                XCTAssertTrue(
                    outcome.renderedText.contains(activeTabURL.host() ?? ""),
                    """
                    Dark Reader's popup rendered without the active tab's host \
                    for \(label). Text: \(outcome.renderedText.prefix(200))
                    """
                )
                assertNoStalledHostCall(outcome.hostCalls, label: label)
            }
        }
    }

    /// The Chrome Web Store is a protected origin in Chrome: it withholds host
    /// access, so `tabs.get` never reports the URL there. Crest grants the
    /// extension's `*://*/*` host permission on that origin instead, which
    /// leaves Dark Reader reporting the store as protected from its own
    /// hardcoded URL list rather than from a missing permission. Both paths
    /// must reach a rendered popup rather than a stalled host call.
    func testLiveDarkReaderPopupReportsTheStoreOriginAsProtected()
        async throws
    {
        try skipUnlessLiveRunRequested()
        let candidate = try await candidate(
            extensionID: darkReaderID,
            slug: "dark-reader"
        )
        let storeURL = try XCTUnwrap(
            URL(string: "https://chromewebstore.google.com/")
        )
        let outcome = try await popupOutcome(
            candidate: candidate,
            extensionID: darkReaderID,
            activeTabURL: storeURL,
            viaRestoration: false
        )
        XCTAssertNotNil(
            outcome.readyMilliseconds,
            """
            Dark Reader's popup stalled on the Chrome Web Store. Host calls: \
            \(outcome.hostCalls)
            """
        )
        XCTAssertTrue(
            outcome.renderedText.contains("protected"),
            """
            Dark Reader stopped reporting the Chrome Web Store as a protected \
            page. Text: \(outcome.renderedText.prefix(300))
            """
        )
    }

    /// Crest presents action popups through `NSPopover` and unloads the popup
    /// web view when a shown popover is toggled closed. A popup that survives
    /// its first load but not a reopen would strand the user on the startup
    /// loader with the popover visible, so drive the real presentation path
    /// across a close and reopen on both an ordinary and a store tab.
    func testLivePopupSurvivesCloseAndReopenThroughRealPresentation()
        async throws
    {
        try skipUnlessLiveRunRequested()
        let candidate = try await candidate(
            extensionID: darkReaderID,
            slug: "dark-reader"
        )
        let urls = [
            try XCTUnwrap(URL(string: "https://example.com/")),
            try XCTUnwrap(URL(string: "https://chromewebstore.google.com/")),
        ]
        for activeTabURL in urls {
            for viaRestoration in [false, true] {
                let outcome = try await popupOutcome(
                    candidate: candidate,
                    extensionID: darkReaderID,
                    activeTabURL: activeTabURL,
                    viaRestoration: viaRestoration,
                    viaPopover: true
                )
                let label =
                    "\(activeTabURL.absoluteString) "
                    + (viaRestoration ? "after restoration" : "after install")
                    + " through the presented popover"
                XCTAssertNotNil(
                    outcome.readyMilliseconds,
                    """
                    A reopened popup never left "Loading, please wait" for \
                    \(label). Host calls: \(outcome.hostCalls). Runtime \
                    errors: \(outcome.contextErrors)
                    """
                )
                assertNoStalledHostCall(outcome.hostCalls, label: label)
            }
        }
    }

    /// The popup a person actually opens is almost never the first thing they
    /// do after launch. A nonpersistent background is evicted seconds into a
    /// session, so the opening `ui-bg-get-data` round trip is answered by a
    /// background that has to be restarted first. Drive that exact shape: idle
    /// past eviction, then present the popup for the first time.
    func testLiveDarkReaderPopupCompletesAfterItsBackgroundIsEvicted()
        async throws
    {
        try skipUnlessLiveRunRequested()
        let candidate = try await candidate(
            extensionID: darkReaderID,
            slug: "dark-reader"
        )
        let activeTabURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let outcome = try await popupOutcome(
            candidate: candidate,
            extensionID: darkReaderID,
            activeTabURL: activeTabURL,
            viaRestoration: false,
            viaPopover: true,
            idleSecondsBeforePresenting: Self.backgroundEvictionIdleSeconds
        )
        XCTAssertNotNil(
            outcome.readyMilliseconds,
            """
            Dark Reader's popup never left "Loading, please wait" when it was \
            opened after its nonpersistent background had been evicted. Host \
            calls: \(outcome.hostCalls). Runtime errors: \
            \(outcome.contextErrors)
            """
        )
        XCTAssertTrue(
            outcome.renderedText.contains(activeTabURL.host() ?? ""),
            """
            Dark Reader's popup rendered without the active tab's host after \
            its background was evicted. Text: \
            \(outcome.renderedText.prefix(200))
            """
        )
        assertNoStalledHostCall(
            outcome.hostCalls,
            label: "an evicted background"
        )
    }

    func testLiveSponsorBlockPopupCompletesOnWatchAndStorePages() async throws {
        try skipUnlessLiveRunRequested()
        let candidate = try await candidate(
            extensionID: sponsorBlockID,
            slug: "sponsorblock-for-youtube-sp"
        )
        let watchURL = try XCTUnwrap(
            URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        )
        let storeURL = try XCTUnwrap(
            URL(string: "https://chromewebstore.google.com/")
        )
        for activeTabURL in [watchURL, storeURL] {
            let outcome = try await popupOutcome(
                candidate: candidate,
                extensionID: sponsorBlockID,
                activeTabURL: activeTabURL,
                viaRestoration: false
            )
            let label = activeTabURL.absoluteString
            XCTAssertFalse(
                outcome.renderedText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty,
                """
                SponsorBlock's popup rendered no content for \(label). Host \
                calls: \(outcome.hostCalls). Runtime errors: \
                \(outcome.contextErrors)
                """
            )
            assertNoStalledHostCall(outcome.hostCalls, label: label)
        }
    }

    func testLiveRaindropPopupRendersItsSignedOutState() async throws {
        try skipUnlessLiveRunRequested()
        let candidate = try await mozillaCandidate(slug: "raindropio")
        let activeTabURL = try XCTUnwrap(
            URL(string: "https://addons.mozilla.org/")
        )
        let outcome = try await popupOutcome(
            candidate: candidate,
            extensionID:
                "jid0-adyhmvsP91nUO8pRv0Mn2VKeB84@jetpack",
            activeTabURL: activeTabURL,
            viaRestoration: false,
            viaPopover: true,
            warmsPopupBeforeMeasurement: false,
            permissionProbeURL: try XCTUnwrap(
                URL(string: "https://api.raindrop.io/v1/user")
            )
        )

        XCTAssertTrue(
            outcome.permissionProbeStatus.map {
                [
                    WKWebExtensionContext.PermissionStatus.grantedImplicitly,
                    .grantedExplicitly,
                ].contains($0)
            } == true,
            "Raindrop's reviewed API host was not granted at installation."
        )
        XCTAssertFalse(
            outcome.renderedText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            """
            Raindrop rendered a blank action popup. Host calls: \
            \(outcome.hostCalls). Runtime errors: \(outcome.contextErrors)
            """
        )
        XCTAssertTrue(
            outcome.hostCalls.contains {
                $0.contains("tabs.query")
                    && $0.contains(activeTabURL.absoluteString)
            },
            """
            Raindrop's activeTab action gesture did not expose the active page \
            URL. Host calls: \(outcome.hostCalls). Runtime errors: \
            \(outcome.contextErrors)
            """
        )
    }

    func testLiveOnePasswordSignedOutActionOpensOnboardingAcrossRestoration() async throws {
        try skipUnlessLiveRunRequested()
        let candidate = try await candidate(
            extensionID: onePasswordID,
            slug: "1password-password-manager"
        )
        for viaRestoration in [false, true] {
            let outcome = try await popupOutcome(
                candidate: candidate,
                extensionID: onePasswordID,
                activeTabURL: try XCTUnwrap(
                    URL(string: "https://fill.dev/form/identity-simple")
                ),
                viaRestoration: viaRestoration,
                viaPopover: true,
                usesEphemeralWebKitStorage: false
            )
            let phase = viaRestoration ? "after restoration" : "after install"

            // Current 1Password clears action.default_popup while it has no
            // accounts or desktop connection; action.onClicked opens setup.
            XCTAssertFalse(outcome.presentsPopup)
            XCTAssertEqual(outcome.actionPageURL?.scheme, "chrome-extension")
            XCTAssertEqual(outcome.actionPageURL?.host, onePasswordID)
            XCTAssertEqual(outcome.actionPageURL?.path, "/app/app.html")
            XCTAssertTrue(
                outcome.actionPageText.contains("Welcome to 1Password")
                    || outcome.actionPageText.contains("Start setup"),
                "1Password did not render its signed-out setup \(phase): \(outcome.actionPageText.prefix(300))")
            let absentCompanions = ["com.1password.1password", "com.1password.1password7"]
            let unexpectedErrors = outcome.contextErrors.filter { error in
                !absentCompanions.contains { error.contains("The native companion \($0) is not installed.") }
            }
            XCTAssertTrue(
                unexpectedErrors.isEmpty,
                "1Password reported runtime errors \(phase): \(unexpectedErrors)"
            )
        }
    }

    /// LastPass has a multi-megabyte service worker and its popup immediately
    /// asks that worker for synchronized state. A URL-less Start Page still
    /// represents Crest's selected tab, so the toolbar action must go through
    /// WebKit's normal perform-action lifecycle instead of displaying a
    /// preloaded popover whose background handshake has not completed.
    func testLiveLastPassPopupRendersSignedOutStateFromStartPage() async throws {
        try skipUnlessLiveRunRequested()
        let candidate = try await candidate(
            extensionID: lastPassID,
            slug: "lastpass-free-password-manager"
        )
        let outcome = try await popupOutcome(
            candidate: candidate,
            extensionID: lastPassID,
            activeTabURL: nil,
            viaRestoration: true,
            viaPopover: true,
            usesEphemeralWebKitStorage: false,
            warmsPopupBeforeMeasurement: false
        )

        XCTAssertTrue(outcome.presentsPopup)
        XCTAssertNotNil(
            outcome.readyMilliseconds,
            """
            LastPass never completed its Start Page popup handshake. Text: \
            \(outcome.renderedText.prefix(300)). Runtime errors: \
            \(outcome.contextErrors)
            """
        )
        XCTAssertFalse(
            outcome.renderedText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            "LastPass presented a blank popup from the Start Page."
        )
    }

    /// LastPass's options page is a useful stress case for tab-hosted extension
    /// pages: its first document fans out into several megabytes of scripts and
    /// styles. The first open must resolve those packaged resources just like a
    /// reload does; requiring the person to reload a blank extension tab is not
    /// a viable options-page lifecycle.
    func testLiveLastPassOptionsPageRendersWithoutManualReload() async throws {
        try skipUnlessLiveRunRequested()
        let candidate = try await candidate(
            extensionID: lastPassID,
            slug: "lastpass-free-password-manager"
        )
        let outcome = try await optionsPageOutcome(
            candidate: candidate,
            extensionID: lastPassID,
            viaRestoration: true
        )

        XCTAssertFalse(
            outcome.firstLoadText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            """
            LastPass's options page was blank on its first open. A manual reload \
            rendered: \(outcome.reloadText.prefix(300)). Navigation failure: \
            \(outcome.navigationFailure ?? "none"). Runtime errors: \
            \(outcome.contextErrors)
            """
        )
        XCTAssertTrue(
            outcome.reloadText.contains("Preferences"),
            "LastPass's options page did not render after a diagnostic reload."
        )
    }

    private func assertNoStalledHostCall(
        _ hostCalls: [String],
        label: String
    ) {
        for call in hostCalls where call.contains("TIMEOUT") {
            XCTFail(
                """
                A supplementary host API probe did not settle for \(label): \(call).
                Full host probe: \(hostCalls).
                """
            )
        }
    }

    private func skipUnlessLiveRunRequested() throws {
        let marker = URL(filePath: "/tmp/CrestRunChromeStoreIntegration")
        guard
            ProcessInfo.processInfo.environment[
                "CREST_RUN_CHROME_STORE_INTEGRATION"
            ] == "1"
                || FileManager.default.fileExists(atPath: marker.path)
        else {
            throw XCTSkip(
                """
                Set CREST_RUN_CHROME_STORE_INTEGRATION=1 to exercise live \
                action popups against current Chrome Web Store packages.
                """
            )
        }
    }

    private enum LiveCandidate {
        case chrome(BrowserChromeWebStoreCandidate)
        case mozilla(BrowserMozillaAddonsCandidate)
    }

    private func candidate(
        extensionID: String,
        slug: String
    ) async throws -> LiveCandidate {
        let item = try XCTUnwrap(
            BrowserChromeWebStoreItem(
                url: URL(
                    string:
                        "https://chromewebstore.google.com/detail/\(slug)/\(extensionID)"
                )!
            )
        )
        // The debug test host carries no Developer ID signature, so the
        // build's own native-messaging capability reads unavailable and the
        // compatibility gate would block password managers before any popup
        // exists to test. These live tests cover the popup lifecycle, not
        // the capability gate, so they run as the entitled release build.
        let candidate = try await BrowserChromeWebStoreProvider(
            nativeMessagingCapability: .available
        ).candidate(for: item)
        print(
            "Live extension package: \(extensionID) version=\(candidate.version ?? "unknown") crxSHA256=\(candidate.source.crxSHA256Hex)"
        )
        return .chrome(candidate)
    }

    private func mozillaCandidate(slug: String) async throws -> LiveCandidate {
        let item = try XCTUnwrap(
            BrowserMozillaAddonsItem(
                url: URL(
                    string:
                        "https://addons.mozilla.org/en-US/firefox/addon/\(slug)/"
                )!
            )
        )
        return .mozilla(
            try await BrowserMozillaAddonsProvider().candidate(for: item)
        )
    }

    private struct PopupOutcome {
        var presentsPopup: Bool
        var readyMilliseconds: Int?
        var renderedText: String
        var hostCalls: [String]
        var contextErrors: [String]
        var permissionProbeStatus: WKWebExtensionContext.PermissionStatus?
        var actionPageURL: URL?
        var actionPageText = ""
    }

    private struct OptionsPageOutcome {
        var firstLoadText: String
        var reloadText: String
        var navigationFailure: String?
        var contextErrors: [String]
    }

    private func optionsPageOutcome(
        candidate: LiveCandidate,
        extensionID: String,
        viaRestoration: Bool
    ) async throws -> OptionsPageOutcome {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-extension-options-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let registryPersistence =
            InMemoryBrowserExtensionRegistryPersistence()
        let profile = BrowsingProfile()
        let targetSpace = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Work",
            symbol: "puzzlepiece.extension.fill",
            accent: .indigo,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let otherSpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Personal",
            symbol: "person.fill",
            accent: .orange,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [targetSpace, otherSpace],
                selectedSpaceID: targetSpace.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )

        func makePool() -> BrowserExtensionControllerPool {
            let pool = BrowserExtensionControllerPool(
                packageStore: BrowserExtensionPackageStore(
                    fileManager: fileManager,
                    rootURL: root,
                    removesRootOnDeinit: false
                ),
                registry: BrowserExtensionRegistry(
                    persistence: registryPersistence
                ),
                storedResourcePreparer: BrowserStoreWebExtensionStoredResourcePreparer(),
                usesEphemeralWebKitStorage: false
            )
            pool.setNativeMessagingHandler(PopupFixtureNativeMessagingHandler(pool: pool, browser: browser))
            return pool
        }

        func attach(
            _ pool: BrowserExtensionControllerPool
        ) -> BrowserPagePool {
            let pages = BrowserPagePool(
                monitorsMemoryPressure: false,
                usesEphemeralWebsiteDataStores: false,
                extensionControllerPool: pool
            )
            pool.connect(browser: browser, pageProvider: pages)
            pages.select(session: browser.session)
            return pages
        }

        var pool = makePool()
        var pages = attach(pool)
        switch candidate {
        case .chrome(let candidate):
            _ = try await pool.installChromeWebStoreExtension(
                candidate,
                in: targetSpace
            )
            _ = try await pool.installChromeWebStoreExtension(
                candidate,
                in: otherSpace
            )
        case .mozilla(let candidate):
            _ = try await pool.installMozillaAddonsExtension(
                candidate,
                in: targetSpace
            )
            _ = try await pool.installMozillaAddonsExtension(
                candidate,
                in: otherSpace
            )
        }

        if viaRestoration {
            pool = makePool()
            pages = attach(pool)
            await pool.restoreEnabledExtensions(in: [targetSpace, otherSpace])
        }
        browser.selectSpace(targetSpace.id)
        pages.select(session: browser.session)
        let targetContext = try XCTUnwrap(
            pool.loadedContext(extensionID: extensionID, in: targetSpace.id)
        )
        _ = try XCTUnwrap(
            pool.loadedContext(extensionID: extensionID, in: otherSpace.id)
        )
        targetContext.isInspectable = true
        pool.openOptionsPage(extensionID: extensionID, in: targetSpace.id)

        let page = try XCTUnwrap(pages.activePage)
        let firstLoadText = await renderedBodyText(in: page.webView)
        let navigationFailure = page.navigationFailure.map {
            String(describing: $0)
        }
        page.webView.reload()
        let reloadText = await renderedBodyText(in: page.webView)
        let contextErrors = Self.errorDescriptions(targetContext.errors)

        _ = try? await pool.deleteData(for: targetSpace)
        _ = try? await pool.deleteData(for: otherSpace)
        try? await WKWebsiteDataStore.remove(forIdentifier: profile.id)
        try? await WKWebsiteDataStore.remove(
            forIdentifier: otherSpace.profile.id
        )
        return OptionsPageOutcome(
            firstLoadText: firstLoadText,
            reloadText: reloadText,
            navigationFailure: navigationFailure,
            contextErrors: contextErrors
        )
    }

    private func renderedBodyText(in webView: WKWebView) async -> String {
        var text = ""
        for _ in 0..<200 {
            text =
                ((try? await webView.evaluateJavaScript(
                    "document.body.innerText"
                )) as? String) ?? ""
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return text
    }

    private func popupOutcome(
        candidate: LiveCandidate,
        extensionID: String,
        activeTabURL: URL?,
        viaRestoration: Bool,
        viaPopover: Bool = false,
        idleSecondsBeforePresenting: Int = 0,
        usesEphemeralWebKitStorage: Bool = true,
        warmsPopupBeforeMeasurement: Bool = true,
        permissionProbeURL: URL? = nil
    ) async throws -> PopupOutcome {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-action-popup-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let registryPersistence =
            InMemoryBrowserExtensionRegistryPersistence()
        let profile = BrowsingProfile()
        let tab = BrowserTab(
            title: "Popup fixture",
            url: activeTabURL,
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Popup fixture",
            symbol: "puzzlepiece.extension.fill",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )

        func makePool() -> BrowserExtensionControllerPool {
            let pool = BrowserExtensionControllerPool(
                packageStore: BrowserExtensionPackageStore(
                    fileManager: fileManager,
                    rootURL: root,
                    removesRootOnDeinit: false
                ),
                registry: BrowserExtensionRegistry(
                    persistence: registryPersistence
                ),
                storedResourcePreparer: BrowserStoreWebExtensionStoredResourcePreparer(),
                usesEphemeralWebKitStorage: usesEphemeralWebKitStorage
            )
            // An available transport whose hosts are all absent: extensions
            // that talk to a companion app must still bring up their popup
            // and report its signed-out state.
            return pool
        }

        // The coordinator only holds the session store weakly, the way the
        // app's own store outlives it, so the fixture must keep the store
        // alive itself or every session-backed call (tabs.create during an
        // extension's install onboarding, most visibly) fails midway.
        var retainedBrowser: BrowserStore?
        var retainedPages: BrowserPagePool?
        func attach(
            to pool: BrowserExtensionControllerPool
        ) -> WKWebView {
            let browser = BrowserStore(
                session: BrowserSession(
                    spaces: [space],
                    selectedSpaceID: space.id
                ),
                persistence: InMemoryBrowserSessionPersistence()
            )
            retainedBrowser = browser
            pool.setNativeMessagingHandler(PopupFixtureNativeMessagingHandler(pool: pool, browser: browser))
            if activeTabURL != nil {
                let pages = BrowserPagePool(
                    monitorsMemoryPressure: false,
                    usesEphemeralWebsiteDataStores: usesEphemeralWebKitStorage,
                    extensionControllerPool: pool)
                retainedPages = pages
                pool.connect(browser: browser, pageProvider: pages)
                pages.select(session: browser.session)
                if let webView = pages.extensionWebView(for: tab.id, in: space.id) {
                    return webView
                }
            }
            let webView = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 900, height: 700),
                configuration: BrowserPageConfiguration.make(
                    for: profile,
                    webExtensionController: pool.controller(for: space)
                )
            )
            pool.connect(
                browser: browser,
                pageProvider: ExtensionPopupPageProviderSpy(
                    webViews: [tab.id: webView]
                )
            )
            return webView
        }

        var pool = makePool()
        var webView = attach(to: pool)
        defer { _ = (retainedBrowser, retainedPages) }
        func cleanUpPersistentStorage() async {
            guard !usesEphemeralWebKitStorage else { return }
            _ = try? await pool.deleteData(for: space)
            try? await WKWebsiteDataStore.remove(forIdentifier: profile.id)
        }
        switch candidate {
        case .chrome(let candidate):
            _ = try await pool.installChromeWebStoreExtension(
                candidate,
                in: space
            )
        case .mozilla(let candidate):
            _ = try await pool.installMozillaAddonsExtension(
                candidate,
                in: space
            )
        }

        if viaRestoration {
            // Stand in for a relaunch: every runtime object is replaced and
            // the extension comes back from persisted installation state
            // alone, so its background content has not run this session.
            if let oldContext = pool.loadedContext(extensionID: extensionID, in: space.id) {
                try pool.controller(for: space).unload(oldContext)
            }
            pool = makePool()
            webView = attach(to: pool)
            await pool.restoreEnabledExtensions(in: [space])
        }

        let context = try XCTUnwrap(
            pool.loadedContext(extensionID: extensionID, in: space.id)
        )
        let permissionProbeStatus = permissionProbeURL.map {
            context.permissionStatus(for: $0)
        }
        context.isInspectable = true
        if let activeTabURL {
            await load(activeTabURL, in: webView)
        }
        if idleSecondsBeforePresenting > 0 {
            try await Task.sleep(for: .seconds(idleSecondsBeforePresenting))
        }

        let adapter = pool.extensionTab(tab.id, in: space.id)
        guard let action = context.action(for: adapter) else {
            let outcome = PopupOutcome(
                presentsPopup: false,
                readyMilliseconds: nil,
                renderedText: "",
                hostCalls: [],
                contextErrors: Self.errorDescriptions(context.errors),
                permissionProbeStatus: permissionProbeStatus
            )
            await cleanUpPersistentStorage()
            return outcome
        }
        let presentsPopup = action.presentsPopup
        if viaPopover {
            let toolbarAction = try XCTUnwrap(
                pool.toolbarActions(in: space.id, tabID: tab.id).first {
                    $0.id == extensionID
                }
            )
            // Drive Crest's public toolbar-action path, including a close and
            // reopen, so this covers WebKit's action/delegate lifecycle rather
            // than only calling the coordinator's popover presenter directly.
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            let anchor = BrowserExtensionPopupAnchor(
                screenPoint: CGPoint(
                    x: window.frame.midX,
                    y: window.frame.midY
                ),
                sourceWindow: window
            )
            // An idle run measures the very first presentation, so it must not
            // be preceded by the close-and-reopen warmup that would restart the
            // background before the measured open.
            let warmupPresentations = warmsPopupBeforeMeasurement ? 2 : 0
            for _ in 0..<warmupPresentations {
                pool.perform(toolbarAction, popupAnchor: anchor)
                try? await Task.sleep(
                    for: BrowserExtensionPopupBackgroundWarmUp.defaultDeadline
                        + .milliseconds(250)
                )
            }
            // A warmed-up run left the popover closed on its second call, so
            // this is the open being measured either way.
            pool.perform(toolbarAction, popupAnchor: anchor)
            // Presentation waits on the extension's background content, so it
            // lands after the call that asked for it returns. Wait it out here
            // rather than polling `popupPopover`, which would preload the popup
            // document the wait exists to hold back.
            try await Task.sleep(
                for: BrowserExtensionPopupBackgroundWarmUp.defaultDeadline
                    + .seconds(1)
            )
        }
        guard let popupWebView = action.popupWebView else {
            let actionPage = retainedPages?.activePage?.webView
            // Onboarding is a normal tab. Give it the same visible viewport
            // that the browser supplies, rather than inspecting a zero-size,
            // unattached page from the page pool.
            let pageWindow = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            if let actionPage {
                pageWindow.contentView = actionPage
                pageWindow.orderFront(nil)
            }
            defer {
                pageWindow.contentView = nil
                pageWindow.orderOut(nil)
            }
            let actionPageText = if let actionPage { await renderedBodyText(in: actionPage) } else { "" }
            let outcome = PopupOutcome(
                presentsPopup: presentsPopup,
                readyMilliseconds: nil,
                renderedText: "",
                hostCalls: [],
                contextErrors: Self.errorDescriptions(context.errors),
                permissionProbeStatus: permissionProbeStatus,
                actionPageURL: actionPage?.url,
                actionPageText: actionPageText
            )
            await cleanUpPersistentStorage()
            return outcome
        }

        var readyMilliseconds: Int?
        let start = Date()
        for _ in 0..<200 {
            let isReady =
                try? await popupWebView.evaluateJavaScript(
                    """
                    (() => {
                        const loader = document.querySelector('.loader');
                        // No loader yet means the popup document has not
                        // parsed, which must not read as readiness.
                        if (loader) {
                            return loader.classList
                                .contains('loader--complete');
                        }
                        return document.readyState === 'complete'
                            && document.body.innerText.trim().length > 0;
                    })()
                    """
                ) as? Bool
            if isReady == true {
                readyMilliseconds = Int(
                    Date().timeIntervalSince(start) * 1000
                )
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let renderedText =
            ((try? await popupWebView.evaluateJavaScript(
                "document.body.innerText"
            )) as? String) ?? ""
        let hostCalls =
            ((try? await popupWebView.callAsyncJavaScript(
                Self.hostCallProbe,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )) as? String).map(Self.decode) ?? []
        let outcome = PopupOutcome(
            presentsPopup: presentsPopup,
            readyMilliseconds: readyMilliseconds,
            renderedText: renderedText,
            hostCalls: hostCalls,
            contextErrors: Self.errorDescriptions(context.errors),
            permissionProbeStatus: permissionProbeStatus
        )
        if hostCalls.contains(where: { $0.contains("TIMEOUT") }) {
            print(
                "Popup probe timeout: extension=\(extensionID) restored=\(viaRestoration) readyMilliseconds=\(String(describing: readyMilliseconds)) pageLoading=\(webView.isLoading) pageURL=\(webView.url?.absoluteString ?? "none") calls=\(hostCalls)"
            )
        }
        await cleanUpPersistentStorage()
        return outcome
    }

    private static func errorDescriptions(_ errors: [any Error]) -> [String] {
        errors.map { error in
            let cocoaError = error as NSError
            return "\(cocoaError.domain)#\(cocoaError.code): "
                + "\(cocoaError.localizedDescription) "
                + "\(cocoaError.userInfo)"
        }
    }

    private func load(_ url: URL, in webView: WKWebView) async {
        webView.load(URLRequest(url: url))
        for _ in 0..<200 {
            try? await Task.sleep(for: .milliseconds(50))
            if !webView.isLoading { break }
        }
        // Content scripts settle shortly after the load finishes.
        try? await Task.sleep(for: .milliseconds(500))
    }

    /// Times the host calls Dark Reader's `collectData` awaits. `getTabURL`
    /// tries `tabs.get` first and falls back to `scripting.executeScript`
    /// against the active tab, so both must settle on every origin.
    private static let hostCallProbe = #"""
        const results = [];
        const race = async (name, run) => {
            const started = performance.now();
            let outcome;
            try {
                outcome = await Promise.race([
                    Promise.resolve().then(run).then(
                        (value) => "resolved: " +
                            JSON.stringify(value ?? null).slice(0, 160)
                    ),
                    new Promise((resolve) =>
                        setTimeout(() => resolve("TIMEOUT"), 5000)
                    )
                ]);
            } catch (error) {
                outcome = "threw: " + String(error).slice(0, 160);
            }
            results.push({
                t: Math.round(performance.now() - started),
                kind: name,
                detail: outcome
            });
        };

        let activeTabID = null;
        await race("tabs.query", async () => {
            const tabs = await chrome.tabs.query({
                active: true,
                lastFocusedWindow: true,
                windowType: "normal"
            });
            activeTabID = tabs && tabs[0] ? tabs[0].id : null;
            return (tabs ?? []).map((tab) => ({ id: tab.id, url: tab.url }));
        });
        await race("tabs.get", async () => {
            if (activeTabID === null) { return "no active tab"; }
            const tab = await chrome.tabs.get(activeTabID);
            return { url: tab.url };
        });
        await race("scripting.executeScript", async () => {
            if (activeTabID === null) { return "no active tab"; }
            return await chrome.scripting.executeScript({
                target: { tabId: activeTabID, frameIds: [0] },
                world: "MAIN",
                injectImmediately: true,
                func: () => window.location.href
            });
        });
        await race("storage.local.get", async () =>
            await new Promise((resolve) =>
                chrome.storage.local.get({ installation: {} }, resolve)
            )
        );
        return JSON.stringify(results);
        """#

    private static func decode(_ payload: String) -> [String] {
        guard let data = payload.data(using: .utf8),
            let entries = try? JSONSerialization.jsonObject(with: data)
                as? [[String: Any]]
        else {
            return [payload]
        }
        return entries.map { entry in
            let time = entry["t"] as? Int ?? 0
            let kind = entry["kind"] as? String ?? "?"
            let detail = entry["detail"] as? String ?? ""
            return "\(kind) [\(time)ms] \(detail)"
        }
    }
}

@MainActor
private final class PopupFixtureNativeMessagingHandler:
    BrowserExtensionNativeMessagingHandling
{
    let capability = BrowserExtensionNativeMessagingCapability.available
    // Use the real internal broker. Only external companions and notification
    // delivery are isolated; bypassing preparation or rejecting broker calls
    // would exercise a different extension runtime from the app.
    private let service: BrowserNativeMessagingService

    init(pool: BrowserExtensionControllerPool, browser: BrowserStore) {
        let sidebar = BrowserExtensionSidebarStore(behaviorPersistence: InMemoryBrowserExtensionSidebarBehaviorStore())
        let tabGroups = browser.extensionTabGroups
        let rules = BrowserExtensionDeclarativeNetRequestStore(
            persistence: InMemoryBrowserExtensionDeclarativeNetRequestStore())
        pool.setSidebarService(sidebar)
        pool.setTabGroupService(tabGroups)
        pool.setDeclarativeNetRequestService(rules)
        service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(searchDirectories: []),
            notificationService: BrowserExtensionNotificationService(
                center: InMemoryBrowserExtensionNotificationCenter()),
            sidebarService: sidebar,
            sidebarEventMessage: { [weak pool] in pool?.sidebarEventMessage($0) },
            tabGroupService: tabGroups,
            tabGroupEventMessage: { [weak pool] in pool?.tabGroupEventMessage($0) ?? [:] },
            declarativeNetRequestService: rules,
            declarativeNetRequestEventMessage: { [weak pool] in pool?.declarativeNetRequestEventMessage($0) ?? [:] },
            externalMessageService: pool.externalMessageService,
            externalMessageEventMessage: { [weak pool] in pool?.externalMessageEventMessage($0) },
            webpageMenuRegistry: pool.webpageMenuRegistry)
    }

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity?,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        service.sendMessage(
            message, applicationIdentifier: applicationIdentifier, extensionIdentity: extensionIdentity,
            authorization: authorization, replyHandler: replyHandler)
    }

    func connect(
        port: WKWebExtension.MessagePort,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity?,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        completionHandler: @escaping (Error?) -> Void
    ) {
        service.connect(
            port: port, extensionIdentity: extensionIdentity, authorization: authorization,
            completionHandler: completionHandler)
    }
}

@MainActor
private final class ExtensionPopupPageProviderSpy:
    BrowserExtensionPageProviding
{
    private let webViews: [TabID: WKWebView]

    init(webViews: [TabID: WKWebView]) {
        self.webViews = webViews
    }

    func extensionWebView(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> WKWebView? {
        webViews[tabID]
    }

    /// Mirrors `BrowserPagePool`: a synchronous read of last known state that
    /// never starts a probe, so it cannot stall a `tabs` query.
    func extensionReaderModeState(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserReaderModeState {
        .unavailable
    }

    func setExtensionReaderModeActive(
        _ isActive: Bool,
        for tabID: TabID,
        in spaceID: SpaceID
    ) async throws {
        throw BrowserReaderModeError.articleUnavailable
    }

    func extensionWindowGeometry(
        in spaceID: SpaceID
    ) -> BrowserExtensionWindowGeometry {
        .unavailable
    }

    func prepareExtensionSelection(session: BrowserSession) {}

    func select(session: BrowserSession) {}
}
