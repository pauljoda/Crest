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

    func testLiveOnePasswordPopupCompletesItsBackgroundHandshake() async throws {
        try skipUnlessLiveRunRequested()
        let candidate = try await candidate(
            extensionID: onePasswordID,
            slug: "1password-password-manager"
        )
        let outcome = try await popupOutcome(
            candidate: candidate,
            extensionID: onePasswordID,
            activeTabURL: try XCTUnwrap(
                URL(string: "https://fill.dev/form/identity-simple")
            ),
            viaRestoration: false,
            viaPopover: true
        )

        XCTAssertTrue(outcome.presentsPopup)
        XCTAssertNotNil(
            outcome.readyMilliseconds,
            """
            1Password's popup never received its initial view from the \
            background worker. Text: \(outcome.renderedText.prefix(300)). \
            Runtime errors: \(outcome.contextErrors)
            """
        )
        XCTAssertFalse(
            outcome.renderedText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            "1Password left only its loading spinner visible."
        )
    }

    private func assertNoStalledHostCall(
        _ hostCalls: [String],
        label: String
    ) {
        for call in hostCalls where call.contains("TIMEOUT") {
            XCTFail(
                """
                A host call the popup depends on never settled for \(label): \
                \(call). Dark Reader's background answers `ui-bg-get-data` \
                without a `.catch` and its popup request has no timeout, so a \
                stalled host call strands the popup on its startup loader.
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

    private func candidate(
        extensionID: String,
        slug: String
    ) async throws -> BrowserChromeWebStoreCandidate {
        let item = try XCTUnwrap(
            BrowserChromeWebStoreItem(
                url: URL(
                    string:
                        "https://chromewebstore.google.com/detail/\(slug)/\(extensionID)"
                )!
            )
        )
        return try await BrowserChromeWebStoreProvider().candidate(for: item)
    }

    private struct PopupOutcome {
        var presentsPopup: Bool
        var readyMilliseconds: Int?
        var renderedText: String
        var hostCalls: [String]
        var contextErrors: [String]
    }

    private func popupOutcome(
        candidate: BrowserChromeWebStoreCandidate,
        extensionID: String,
        activeTabURL: URL,
        viaRestoration: Bool,
        viaPopover: Bool = false,
        idleSecondsBeforePresenting: Int = 0
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
            BrowserExtensionControllerPool(
                packageStore: BrowserExtensionPackageStore(
                    fileManager: fileManager,
                    rootURL: root,
                    removesRootOnDeinit: false
                ),
                registry: BrowserExtensionRegistry(
                    persistence: registryPersistence
                )
            )
        }

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
        _ = try await pool.installChromeWebStoreExtension(candidate, in: space)

        if viaRestoration {
            // Stand in for a relaunch: every runtime object is replaced and
            // the extension comes back from persisted installation state
            // alone, so its background content has not run this session.
            pool = makePool()
            webView = attach(to: pool)
            await pool.restoreEnabledExtensions(in: [space])
        }

        let context = try XCTUnwrap(
            pool.loadedContext(extensionID: extensionID, in: space.id)
        )
        context.isInspectable = true
        await load(activeTabURL, in: webView)
        if idleSecondsBeforePresenting > 0 {
            try await Task.sleep(for: .seconds(idleSecondsBeforePresenting))
        }

        let adapter = pool.extensionTab(tab.id, in: space.id)
        guard let action = context.action(for: adapter) else {
            return PopupOutcome(
                presentsPopup: false,
                readyMilliseconds: nil,
                renderedText: "",
                hostCalls: [],
                contextErrors: context.errors.map(\.localizedDescription)
            )
        }
        let presentsPopup = action.presentsPopup
        if viaPopover {
            // Crest presents through `action.popupPopover` and toggles a shown
            // popover closed with `action.closePopup()`, which unloads the
            // popup web view. Drive that exact path, including a close and
            // reopen, so a popup that only fails on its second load is caught.
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
            let coordinator = pool.tabWindowCoordinator
            // An idle run measures the very first presentation, so it must not
            // be preceded by the close-and-reopen warmup that would restart the
            // background before the measured open.
            let warmupPresentations = idleSecondsBeforePresenting > 0 ? 0 : 2
            for _ in 0..<warmupPresentations {
                guard
                    coordinator.presentActionPopup(action, anchor: anchor)
                else {
                    return PopupOutcome(
                        presentsPopup: presentsPopup,
                        readyMilliseconds: nil,
                        renderedText: "presentActionPopup refused",
                        hostCalls: [],
                        contextErrors: context.errors.map(
                            \.localizedDescription
                        )
                    )
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            // A warmed-up run left the popover closed on its second call, so
            // this is the open being measured either way.
            _ = coordinator.presentActionPopup(action, anchor: anchor)
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
            return PopupOutcome(
                presentsPopup: presentsPopup,
                readyMilliseconds: nil,
                renderedText: "",
                hostCalls: [],
                contextErrors: context.errors.map(\.localizedDescription)
            )
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

        return PopupOutcome(
            presentsPopup: presentsPopup,
            readyMilliseconds: readyMilliseconds,
            renderedText: renderedText,
            hostCalls: hostCalls,
            contextErrors: context.errors.map(\.localizedDescription)
        )
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
