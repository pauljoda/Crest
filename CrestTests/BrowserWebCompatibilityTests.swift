import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWebCompatibilityTests: XCTestCase {

    func testProductionWebPageExposesNotificationsWithoutWebPushHosting() async throws {
        let profile = BrowsingProfile()
        let webView = WKWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(for: profile)
        )

        try await loadFixture(on: webView, origin: URL(string: "https://push.crest.test/")!)
        let capabilities = try await jsonResult(
            from: webView,
            script: """
                return JSON.stringify({
                    notificationsAPI: typeof Notification === 'function',
                    notificationPermission: Notification.permission,
                    pushAPI: typeof PushManager === 'function',
                    serviceWorkerPushManager: typeof ServiceWorkerRegistration === 'function'
                        && 'pushManager' in ServiceWorkerRegistration.prototype
                });
                """
        )

        XCTAssertEqual(capabilities["notificationsAPI"] as? Bool, true)
        XCTAssertEqual(capabilities["notificationPermission"] as? String, "default")
        XCTAssertEqual(capabilities["pushAPI"] as? Bool, false)
        XCTAssertEqual(capabilities["serviceWorkerPushManager"] as? Bool, false)

        await removeDataStore(profile.id)
    }

    func testProductionWebPageExposesWebAuthenticationOnASecureOrigin() async throws {
        let profile = BrowsingProfile()
        let webView = WKWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(for: profile)
        )

        try await loadFixture(on: webView, origin: URL(string: "https://passkeys.crest.test/")!)
        let capabilities = try await jsonResult(
            from: webView,
            script: """
                return JSON.stringify({
                    secureContext: window.isSecureContext,
                    credentialsContainer: typeof navigator.credentials === 'object',
                    credentialCreate: typeof navigator.credentials?.create === 'function',
                    credentialGet: typeof navigator.credentials?.get === 'function',
                    publicKeyCredential: typeof PublicKeyCredential === 'function',
                    platformAuthenticatorProbe:
                        typeof PublicKeyCredential?.isUserVerifyingPlatformAuthenticatorAvailable
                            === 'function'
                });
                """
        )

        for capability in [
            "secureContext",
            "credentialsContainer",
            "credentialCreate",
            "credentialGet",
            "publicKeyCredential",
            "platformAuthenticatorProbe",
        ] {
            XCTAssertEqual(
                capabilities[capability] as? Bool,
                true,
                "Missing WebAuthentication capability: \(capability)"
            )
        }

        await removeDataStore(profile.id)
    }

    func testLocalStorageAndIndexedDBRemainInsideOneSpaceProfile() async throws {
        let profileA = BrowsingProfile()
        let profileB = BrowsingProfile()
        let origin = URL(string: "https://storage.crest.test/")!
        let dataStoreA = BrowserWebsiteDataStore.persistent(for: profileA)
        let dataStoreB = BrowserWebsiteDataStore.persistent(for: profileB)

        do {
            let pageA = WKWebView(
                frame: .zero,
                configuration: BrowserPageConfiguration.make(
                    for: profileA,
                    websiteDataStore: dataStoreA
                )
            )
            let pageB = WKWebView(
                frame: .zero,
                configuration: BrowserPageConfiguration.make(
                    for: profileB,
                    websiteDataStore: dataStoreB
                )
            )
            try await loadFixture(on: pageA, origin: origin)
            try await loadFixture(on: pageB, origin: origin)

            let storedValue = try await stringResult(
                from: pageA,
                script: "localStorage.setItem('space-token', 'space-a'); return localStorage.getItem('space-token');"
            )
            let indexedDBValue = try await stringResult(from: pageA, script: indexedDBRoundTripScript)
            let cacheStorageValue = try await stringResult(from: pageA, script: cacheStorageWriteScript)
            let otherSpaceValue = try await nullableStringResult(
                from: pageB,
                script: "return localStorage.getItem('space-token');"
            )
            let otherSpaceCache = try await nullableStringResult(
                from: pageB,
                script: cacheStorageReadScript
            )

            XCTAssertEqual(storedValue, "space-a")
            XCTAssertEqual(indexedDBValue, "indexed-db-ready")
            XCTAssertEqual(cacheStorageValue, "cache-ready")
            XCTAssertNil(otherSpaceValue)
            XCTAssertNil(otherSpaceCache)

            let rehydratedA = WKWebView(
                frame: .zero,
                configuration: BrowserPageConfiguration.make(
                    for: profileA,
                    websiteDataStore: BrowserWebsiteDataStore.persistent(
                        for: profileA
                    )
                )
            )
            try await loadFixture(on: rehydratedA, origin: origin)
            let rehydratedValue = try await stringResult(
                from: rehydratedA,
                script: "return localStorage.getItem('space-token');"
            )
            let rehydratedCache = try await nullableStringResult(
                from: rehydratedA,
                script: cacheStorageReadScript
            )
            XCTAssertEqual(rehydratedValue, "space-a")
            XCTAssertEqual(rehydratedCache, "cache-ready")
        }

        await removeDataStore(profileA.id)
        await removeDataStore(profileB.id)
    }

    func testUnapprovedAutomaticWindowOpenIsBlockedAndCoalesced() async throws {
        let origin = try XCTUnwrap(URL(string: "https://blocked-popups.crest.test/"))
        let openerTab = BrowserTab(title: "Opener", url: nil, placement: .current)
        let profile = BrowsingProfile()
        let space = makeSpace(profile: profile, tabs: [openerTab])
        let store = BrowserStore.hostingPages(
            BrowserSession(spaces: [space])
        )
        let pool = BrowserPagePool(browser: store, popupTabHost: store.popupTabHost)

        do {
            pool.select(session: store.presented)
            let opener = try XCTUnwrap(pool.activePage)
            opener.webView.loadSimulatedRequest(
                URLRequest(url: origin),
                responseHTML: try blockedPopupFixtureHTML()
            )
            try await waitUntil("the popup blocker fixture to load") {
                opener.live.documentURL == origin && !opener.live.isLoading
            }

            XCTAssertFalse(
                opener.webView.configuration.preferences
                    .javaScriptCanOpenWindowsAutomatically
            )
            try await waitUntil("all automatic window requests to run") {
                try await self.intResult(
                    from: opener.webView,
                    script: "return globalThis.automaticPopupResults.length;"
                ) == 3
            }
            let openResults = try await stringResult(
                from: opener.webView,
                script: "return globalThis.automaticPopupResults.join(',');"
            )

            XCTAssertEqual(openResults, "null,null,null")
            XCTAssertEqual(store.selectedSpace?.tabs.map(\.id), [openerTab.id])
            XCTAssertEqual(
                opener.blockedPopupState.notice,
                BrowserBlockedPopupNotice(
                    origin: try XCTUnwrap(BrowserSiteOrigin(url: origin)),
                    status: .blocked
                )
            )
            XCTAssertEqual(opener.blockedPopupState.indicationRevision, 1)

            let navigatedOrigin = try XCTUnwrap(
                URL(string: "https://after-blocked-popup.crest.test/?automatic=0")
            )
            opener.webView.loadSimulatedRequest(
                URLRequest(url: navigatedOrigin),
                responseHTML: try blockedPopupFixtureHTML()
            )
            try await waitUntil("navigation away from the blocked document") {
                opener.live.documentURL == navigatedOrigin && !opener.live.isLoading
            }
            XCTAssertNil(
                opener.blockedPopupState.notice,
                "A blocked indication cannot survive top-level navigation."
            )
        }

        await removeDataStore(profile.id)
    }

    func testUnapprovedAutomaticWindowOpenInATransientPageStaysBlocked() async throws {
        let origin = try XCTUnwrap(
            URL(string: "https://transient-blocked-popups.crest.test/")
        )
        let openerTab = BrowserTab(
            title: "Opener",
            url: nil,
            placement: .current
        )
        let profile = BrowsingProfile()
        let space = makeSpace(profile: profile, tabs: [openerTab])
        let store = BrowserStore.hostingPages(
            BrowserSession(spaces: [space])
        )
        let pool = BrowserPagePool(
            browser: store,
            popupTabHost: store.popupTabHost,
            openNewTab: { url in
                _ = store.openNewTab(url: url)
            }
        )

        do {
            let lease = try XCTUnwrap(
                pool.makeTransientPageLease(
                    url: try XCTUnwrap(URL(string: "about:blank")),
                    in: space
                )
            )
            defer { lease.release() }
            let opener = try XCTUnwrap(lease.page)
            opener.webView.loadSimulatedRequest(
                URLRequest(url: origin),
                responseHTML: try blockedPopupFixtureHTML()
            )
            try await waitUntil("the transient popup blocker fixture to load") {
                opener.live.documentURL == origin && !opener.live.isLoading
            }
            try await waitUntil("all transient automatic window requests to run") {
                try await self.intResult(
                    from: opener.webView,
                    script: "return globalThis.automaticPopupResults.length;"
                ) == 3
            }

            let openResults = try await stringResult(
                from: opener.webView,
                script: "return globalThis.automaticPopupResults.join(',');"
            )

            XCTAssertEqual(openResults, "null,null,null")
            XCTAssertTrue(lease.page === opener)
            XCTAssertEqual(store.selectedSpace?.tabs.map(\.id), [openerTab.id])
            XCTAssertEqual(
                opener.blockedPopupState.notice,
                BrowserBlockedPopupNotice(
                    origin: try XCTUnwrap(BrowserSiteOrigin(url: origin)),
                    status: .blocked
                )
            )
            XCTAssertEqual(opener.blockedPopupState.indicationRevision, 1)
        }

        await removeDataStore(profile.id)
    }

    func testPersistentlyDeniedAutomaticWindowOpenStillProducesOneIndication() async throws {
        let origin = try XCTUnwrap(URL(string: "https://denied-popups.crest.test/"))
        let openerTab = BrowserTab(title: "Opener", url: nil, placement: .current)
        let profile = BrowsingProfile()
        let space = makeSpace(profile: profile, tabs: [openerTab])
        let store = BrowserStore.hostingPages(
            BrowserSession(spaces: [space])
        )
        let pool = BrowserPagePool(browser: store, popupTabHost: store.popupTabHost)
        let siteOrigin = try XCTUnwrap(BrowserSiteOrigin(url: origin))

        do {
            pool.permissionCenter.setDecision(
                .denyPersistently,
                for: .popups,
                origin: siteOrigin,
                in: space.id
            )
            pool.select(session: store.presented)
            let opener = try XCTUnwrap(pool.activePage)
            opener.webView.loadSimulatedRequest(
                URLRequest(url: origin),
                responseHTML: try blockedPopupFixtureHTML()
            )
            try await waitUntil("the denied popup fixture to load") {
                opener.live.documentURL == origin && !opener.live.isLoading
            }
            try await waitUntil("all denied automatic requests to run") {
                try await self.intResult(
                    from: opener.webView,
                    script: "return globalThis.automaticPopupResults.length;"
                ) == 3
            }

            let deniedResults = try await stringResult(
                from: opener.webView,
                script: "return globalThis.automaticPopupResults.join(',');"
            )
            XCTAssertEqual(deniedResults, "null,null,null")
            XCTAssertEqual(store.selectedSpace?.tabs.count, 1)
            XCTAssertEqual(opener.blockedPopupState.notice?.origin, siteOrigin)
            XCTAssertEqual(opener.blockedPopupState.indicationRevision, 1)
        }

        await removeDataStore(profile.id)
    }

    func testExplicitTargetBlankRemainsAllowedWithoutPopupPermission() async throws {
        let origin = try XCTUnwrap(URL(string: "https://explicit-popup.crest.test/"))
        let openerTab = BrowserTab(title: "Opener", url: nil, placement: .current)
        let profile = BrowsingProfile()
        let space = makeSpace(profile: profile, tabs: [openerTab])
        let store = BrowserStore.hostingPages(
            BrowserSession(spaces: [space])
        )
        let pool = BrowserPagePool(browser: store, popupTabHost: store.popupTabHost)

        do {
            pool.select(session: store.presented)
            let opener = try XCTUnwrap(pool.activePage)
            opener.webView.loadSimulatedRequest(
                URLRequest(url: origin),
                responseHTML: try blockedPopupFixtureHTML()
            )
            try await waitUntil("the explicit popup fixture to load") {
                opener.live.documentURL == origin && !opener.live.isLoading
            }
            XCTAssertFalse(
                opener.webView.configuration.preferences
                    .javaScriptCanOpenWindowsAutomatically
            )
            // Poll the fixture itself, as the other automatic-popup cases do,
            // so an unmounted page gets a chance to run its scheduled attempts.
            try await waitUntil("all automatic window requests to run") {
                try await self.intResult(
                    from: opener.webView,
                    script: "return globalThis.automaticPopupResults.length;"
                ) == 3
            }
            try await waitUntil("the automatic attempt to be blocked first") {
                opener.blockedPopupState.notice?.status == .blocked
            }

            _ = try await stringResult(
                from: opener.webView,
                script: """
                    document.querySelector('#explicit-target-blank').click();
                    return 'clicked';
                    """
            )

            try await waitUntil("the explicit target blank to be adopted") {
                store.selectedSpace?.tabs.count == 2
            }
            XCTAssertEqual(opener.blockedPopupState.notice?.status, .blocked)
            XCTAssertTrue(pool.activePage?.wasOpenedAsPopup == true)
        }

        await removeDataStore(profile.id)
    }

    func testTransientTargetBlankKeepsOnePageAndNativeHistory() async throws {
        let origin = try XCTUnwrap(
            URL(string: "https://transient-target-blank.crest.test/?automatic=0")
        )
        let destination = try XCTUnwrap(
            URL(string: "about:blank#target-blank")
        )
        let openerTab = BrowserTab(
            title: "Opener",
            url: nil,
            placement: .current
        )
        let profile = BrowsingProfile()
        let space = makeSpace(profile: profile, tabs: [openerTab])
        let store = BrowserStore.hostingPages(
            BrowserSession(spaces: [space])
        )
        let pool = BrowserPagePool(
            browser: store,
            popupTabHost: store.popupTabHost,
            openNewTab: { url in
                _ = store.openNewTab(url: url)
            }
        )

        do {
            let lease = try XCTUnwrap(
                pool.makeTransientPageLease(
                    url: try XCTUnwrap(URL(string: "about:blank")),
                    in: space
                )
            )
            defer { lease.release() }
            let page = try XCTUnwrap(lease.page)
            page.webView.loadSimulatedRequest(
                URLRequest(url: origin),
                responseHTML: try blockedPopupFixtureHTML()
            )
            try await waitUntil("the transient target-blank fixture to load") {
                page.live.documentURL == origin && page.live.title == "Automatic Pop-up Fixture"
            }

            _ = try await stringResult(
                from: page.webView,
                script: """
                    document.querySelector('#explicit-target-blank').click();
                    return 'clicked';
                    """
            )

            try await waitUntil("target blank to navigate the transient page") {
                page.live.documentURL == destination && !page.live.isLoading
            }
            XCTAssertTrue(lease.page === page)
            XCTAssertEqual(store.selectedSpace?.tabs.map(\.id), [openerTab.id])
            XCTAssertTrue(page.live.canGoBack)
            XCTAssertFalse(page.live.canGoForward)
            XCTAssertNil(page.live.failure)

            page.goBack()
            try await waitUntil("target-blank history to return to its source") {
                page.live.documentURL == origin && page.live.title == "Automatic Pop-up Fixture"
            }
            XCTAssertTrue(page.live.canGoForward)

            page.goForward()
            try await waitUntil("target-blank history to move forward") {
                page.live.documentURL == destination && !page.live.isLoading
            }
            XCTAssertTrue(lease.page === page)
            XCTAssertEqual(store.selectedSpace?.tabs.map(\.id), [openerTab.id])
        }

        await removeDataStore(profile.id)
    }

    func testTransientWindowOpenKeepsOnePageAndNativeHistory() async throws {
        let origin = try XCTUnwrap(
            URL(string: "https://transient-window-open.crest.test/?automatic=0")
        )
        let destination = try XCTUnwrap(
            URL(string: "about:blank#window-open")
        )
        let openerTab = BrowserTab(
            title: "Opener",
            url: nil,
            placement: .current
        )
        let profile = BrowsingProfile()
        let space = makeSpace(profile: profile, tabs: [openerTab])
        let store = BrowserStore.hostingPages(
            BrowserSession(spaces: [space])
        )
        let pool = BrowserPagePool(
            browser: store,
            popupTabHost: store.popupTabHost,
            openNewTab: { url in
                _ = store.openNewTab(url: url)
            }
        )

        do {
            let lease = try XCTUnwrap(
                pool.makeTransientPageLease(
                    url: try XCTUnwrap(URL(string: "about:blank")),
                    in: space
                )
            )
            defer { lease.release() }
            let page = try XCTUnwrap(lease.page)
            page.webView.loadSimulatedRequest(
                URLRequest(url: origin),
                responseHTML: try blockedPopupFixtureHTML()
            )
            try await waitUntil("the transient window-open fixture to load") {
                page.live.documentURL == origin && page.live.title == "Automatic Pop-up Fixture"
            }

            _ = try await stringResult(
                from: page.webView,
                script: """
                    document.querySelector('#explicit-window-open').click();
                    return 'clicked';
                    """
            )

            try await waitUntil("window.open to navigate the transient page") {
                page.live.documentURL == destination && !page.live.isLoading
            }
            XCTAssertTrue(lease.page === page)
            XCTAssertEqual(store.selectedSpace?.tabs.map(\.id), [openerTab.id])
            XCTAssertTrue(page.live.canGoBack)
            XCTAssertFalse(page.live.canGoForward)
            XCTAssertNil(page.live.failure)

            page.goBack()
            try await waitUntil("window-open history to return to its source") {
                page.live.documentURL == origin && page.live.title == "Automatic Pop-up Fixture"
            }
            XCTAssertTrue(page.live.canGoForward)

            page.goForward()
            try await waitUntil("window-open history to move forward") {
                page.live.documentURL == destination && !page.live.isLoading
            }
            XCTAssertTrue(lease.page === page)
            XCTAssertEqual(store.selectedSpace?.tabs.map(\.id), [openerTab.id])
        }

        await removeDataStore(profile.id)
    }

    func testScriptedWindowOpenAdoptsAPopupThatKeepsItsOpener() async throws {
        let origin = try XCTUnwrap(URL(string: "https://popups.crest.test/"))
        let openerTab = BrowserTab(title: "Opener", url: nil, placement: .current)
        let profile = BrowsingProfile()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Popups",
            symbol: "macwindow.on.rectangle",
            accent: .teal,
            folders: [],
            tabs: [openerTab],
            browsingPreferences: BrowserSpaceBrowsingPreferences(
                searchProvider: .google,
                currentTabCleanupPolicy: .never,
                contentBlockingPolicy: .off
            )
        )
        let store = BrowserStore.hostingPages(
            BrowserSession(spaces: [space])
        )
        let pool = BrowserPagePool(
            browser: store,
            popupTabHost: store.popupTabHost
        )

        do {
            pool.select(session: store.presented)
            let opener = try XCTUnwrap(pool.activePage)
            // A saved allow decision enables genuinely automatic windows for
            // this top-level origin. User-activated windows do not need it.
            pool.permissionCenter.setDecision(
                .grantPersistently,
                for: .popups,
                origin: try XCTUnwrap(BrowserSiteOrigin(url: origin)),
                in: space.id
            )
            opener.synchronizePopupPermission(for: origin)
            XCTAssertTrue(
                opener.webView.configuration.preferences
                    .javaScriptCanOpenWindowsAutomatically
            )
            opener.webView.loadSimulatedRequest(
                URLRequest(url: origin),
                responseHTML: fixtureHTML
            )
            try await waitUntil("the opener fixture to load") {
                opener.live.documentURL == origin && !opener.live.isLoading
            }
            let openResult = try await stringResult(
                from: opener.webView,
                script: """
                    globalThis.popup = window.open();
                    return globalThis.popup === null ? 'null' : 'window';
                    """
            )

            XCTAssertEqual(
                openResult,
                "window",
                "window.open() must hand the page a real window. Core error: \(store.localSyncErrorDescription ?? "none")"
            )
            let popupTab = try XCTUnwrap(
                store.selectedSpace?.tabs.first { $0.id != openerTab.id }
            )
            XCTAssertEqual(store.selectedTab?.id, popupTab.id)
            XCTAssertEqual(pool.activeTabID, popupTab.id)
            let popupPage = try XCTUnwrap(pool.activePage)
            XCTAssertFalse(popupPage === opener)
            XCTAssertTrue(popupPage.wasOpenedAsPopup)

            let hasOpener = try await boolResult(
                from: popupPage.webView,
                script: "return window.opener !== null && window.opener !== undefined;"
            )
            XCTAssertTrue(hasOpener, "An adopted popup must keep window.opener.")

            _ = try await stringResult(
                from: opener.webView,
                script: """
                    globalThis.popup.document.write('<p id="written">adopted</p>');
                    globalThis.popup.document.close();
                    return 'written';
                    """
            )
            let writtenText = try await stringResult(
                from: popupPage.webView,
                script: "return document.querySelector('#written')?.textContent ?? '';"
            )
            XCTAssertEqual(
                writtenText,
                "adopted",
                "document.write into an about:blank popup must render."
            )

            _ = try await stringResult(
                from: popupPage.webView,
                script: """
                    window.opener.crestPopupSignal = 'reached-opener';
                    return 'sent';
                    """
            )
            let signal = try await stringResult(
                from: opener.webView,
                script: "return globalThis.crestPopupSignal ?? '';"
            )
            XCTAssertEqual(
                signal,
                "reached-opener",
                "A popup must be able to talk back to its opener."
            )

            _ = try? await popupPage.webView.evaluateJavaScript("window.close();")
            try await waitUntil("window.close() to close the popup's tab") {
                store.selectedSpace?.tabs.contains { $0.id == popupTab.id } == false
            }
            XCTAssertEqual(
                store.selectedSpace?.archivedTabs.last?.tab.id,
                popupTab.id
            )
            XCTAssertEqual(store.selectedTab?.id, openerTab.id)
        }

        await removeDataStore(profile.id)
    }

    private func fixtureURL(_ serverURL: URL, run: String, tab: Int) throws -> URL {
        try XCTUnwrap(
            URL(
                string: "performance.html?run=\(run)&tab=\(tab)",
                relativeTo: serverURL
            )?.absoluteURL
        )
    }

    private func makeSpace(
        profile: BrowsingProfile,
        tabs: [BrowserTab]
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "State",
            symbol: "clock.arrow.circlepath",
            accent: .teal,
            folders: [],
            tabs: tabs,
            browsingPreferences: BrowserSpaceBrowsingPreferences(
                searchProvider: .google,
                currentTabCleanupPolicy: .never,
                contentBlockingPolicy: .off
            )
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(10),
        condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for \(description).")
    }

    private var fixtureHTML: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>#status { display: grid; grid-template-columns: 1fr; }</style>
        </head>
        <body>
          <main id="status">loading</main>
          <input id="files" type="file" multiple>
          <script>document.querySelector('#status').textContent = 'ready';</script>
        </body>
        </html>
        """
    }

    private func blockedPopupFixtureHTML() throws -> String {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/BlockedPopups/blocked-popups.html")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private var indexedDBRoundTripScript: String {
        """
        return await new Promise((resolve, reject) => {
            const request = indexedDB.open('crest-compatibility', 1);
            request.onupgradeneeded = () => request.result.createObjectStore('values');
            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
                const database = request.result;
                const write = database.transaction('values', 'readwrite');
                write.objectStore('values').put('indexed-db-ready', 'probe');
                write.onerror = () => reject(write.error);
                write.oncomplete = () => {
                    const read = database.transaction('values').objectStore('values').get('probe');
                    read.onerror = () => reject(read.error);
                    read.onsuccess = () => resolve(read.result);
                };
            };
        });
        """
    }

    private var cacheStorageWriteScript: String {
        """
        const cache = await caches.open('crest-space-cache');
        await cache.put('/space-token', new Response('cache-ready'));
        return await (await cache.match('/space-token')).text();
        """
    }

    private var cacheStorageReadScript: String {
        """
        const response = await caches.match('/space-token');
        return response ? await response.text() : null;
        """
    }

    private func loadFixture(on page: WKWebView, origin: URL) async throws {
        let request = URLRequest(url: origin)
        let waiter = NavigationWaiter(webView: page)
        try await waiter.load(simulatedRequest: request, responseHTML: fixtureHTML)
    }

    private func jsonResult(from page: WKWebView, script: String) async throws -> [String: Any] {
        let json = try await stringResult(from: page, script: script)
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func stringResult(from page: WKWebView, script: String) async throws -> String {
        let value = try await page.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(value as? String)
    }

    private func boolResult(from page: WKWebView, script: String) async throws -> Bool {
        let value = try await page.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(value as? Bool)
    }

    private func intResult(from page: WKWebView, script: String) async throws -> Int {
        let value = try await page.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap((value as? NSNumber)?.intValue)
    }

    private func nullableStringResult(from page: WKWebView, script: String) async throws -> String? {
        let value = try await page.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        if value is NSNull || value == nil { return nil }
        return try XCTUnwrap(value as? String)
    }

    private func removeDataStore(_ identifier: UUID) async {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in
                continuation.resume()
            }
        }
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func load(simulatedRequest request: URLRequest, responseHTML: String) async throws {
        guard let webView else { throw NavigationWaiterError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadSimulatedRequest(request, responseHTML: responseHTML)
        }
    }

    func load(_ request: URLRequest) async throws {
        guard let webView else { throw NavigationWaiterError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(request)
        }
    }

    func reload() async throws {
        guard let webView else { throw NavigationWaiterError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard webView.reload() != nil else {
                self.continuation = nil
                continuation.resume(throwing: NavigationWaiterError.navigationUnavailable)
                return
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private enum NavigationWaiterError: Error {
    case releasedWebView
    case navigationUnavailable
}
