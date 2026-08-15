import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWebCompatibilityTests: XCTestCase {
    func testResidentPageSwitchingDoesNotRefetchUntilIdleUnload() async throws {
        let serverURL = URL(
            string: ProcessInfo.processInfo.environment["CREST_NETWORK_FIXTURE_URL"]
                ?? "http://127.0.0.1:18768/"
        )!
        guard let initialMetrics = try? await networkFixtureMetrics(at: serverURL),
            initialMetrics.server == "crest-network-fixture-v1"
        else {
            throw XCTSkip("The checked-in network fixture server is unavailable.")
        }

        try await resetNetworkFixtureMetrics(at: serverURL)
        let runID = UUID().uuidString
        let urls = try (1...3).map { tabIndex in
            try XCTUnwrap(
                URL(
                    string: "performance.html?run=\(runID)&tab=\(tabIndex)",
                    relativeTo: serverURL
                )?.absoluteURL
            )
        }
        let tabs = urls.enumerated().map { index, url in
            BrowserTab(
                title: "Network \(index + 1)",
                url: url,
                placement: .current
            )
        }
        let requestTargets = urls.map { url in
            url.query.map { "\(url.path)?\($0)" } ?? url.path
        }
        let profile = BrowsingProfile()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: profile,
            name: "Network",
            symbol: "network",
            accent: .teal,
            folders: [],
            tabs: tabs,
            browsingPreferences: BrowserSpaceBrowsingPreferences(
                searchProvider: .google,
                currentTabCleanupPolicy: .never,
                contentBlockingPolicy: .off
            ),
            selectedTabID: tabs[0].id
        )
        let pool = BrowserPagePool()

        do {
            pool.select(tab: tabs[0], space: space)
            let firstPage = try await waitForActivePage(in: pool, at: urls[0])
            pool.select(tab: tabs[1], space: space)
            _ = try await waitForActivePage(in: pool, at: urls[1])

            let initiallyLoaded = try await networkFixtureMetrics(at: serverURL)
            XCTAssertEqual(initiallyLoaded.requests[requestTargets[0]], 1)
            XCTAssertEqual(initiallyLoaded.requests[requestTargets[1]], 1)

            pool.select(tab: tabs[0], space: space)
            XCTAssertTrue(pool.activePage === firstPage)
            try await Task.sleep(for: .milliseconds(300))
            let afterRetainedSwitch = try await networkFixtureMetrics(at: serverURL)
            XCTAssertEqual(
                afterRetainedSwitch.pageResourceRequests,
                initiallyLoaded.pageResourceRequests,
                "Switching back to a resident page must refetch none of it."
            )

            pool.select(tab: tabs[2], space: space)
            _ = try await waitForActivePage(in: pool, at: urls[2])
            pool.unloadPage(for: tabs[1].id)
            XCTAssertFalse(pool.containsResidentPage(for: tabs[1].id))

            pool.select(tab: tabs[1], space: space)
            _ = try await waitForActivePage(in: pool, at: urls[1])
            let afterRehydration = try await networkFixtureMetrics(at: serverURL)
            XCTAssertEqual(afterRehydration.requests[requestTargets[0]], 1)
            XCTAssertEqual(afterRehydration.requests[requestTargets[1]], 2)
            XCTAssertEqual(afterRehydration.requests[requestTargets[2]], 1)
        } catch {
            pool.reconcile(validTabIDs: [])
            await removeDataStore(profile.id)
            throw error
        }

        pool.reconcile(validTabIDs: [])
        await removeDataStore(profile.id)
    }

    func testAnIdleUnloadedTabComesBackWithItsHistoryAndScrollPosition() async throws {
        let serverURL = try await requireNetworkFixture()
        let runID = UUID().uuidString
        let firstURL = try fixtureURL(serverURL, run: runID, tab: 1)
        let secondURL = try fixtureURL(serverURL, run: runID, tab: 2)
        var stateful = BrowserTab(title: "Stateful", url: firstURL, placement: .current)
        let other = BrowserTab(
            title: "Other",
            url: try fixtureURL(serverURL, run: runID, tab: 3),
            placement: .current
        )
        let profile = BrowsingProfile()
        let space = makeSpace(profile: profile, tabs: [stateful, other])
        let archive = try makeTabStateArchive()
        let pool = BrowserPagePool(tabStateArchive: archive)

        do {
            pool.select(tab: stateful, space: space)
            let originalPage = try await waitForActivePage(in: pool, at: firstURL)
            originalPage.webView.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
            originalPage.load(secondURL)
            _ = try await waitForActivePage(in: pool, at: secondURL)
            let stateBeforeScrolling = originalPage.interactionState
            _ = try await stringResult(
                from: originalPage.webView,
                script: "window.scrollTo(0, 700); return 'scrolled';"
            )
            let scrolledOffset = try await scrollOffset(of: originalPage.webView)
            XCTAssertGreaterThan(scrolledOffset, 0)
            // WebKit folds the scroll offset of the current back/forward item into
            // `interactionState` a beat after the scroll itself, so the state is
            // only worth archiving once it has changed. Production never notices:
            // a page is unloaded long after the user stopped touching it.
            try await waitUntil("WebKit to fold the scroll offset into its state") {
                originalPage.interactionState != stateBeforeScrolling
            }
            // The store keeps a tab's URL in step with its page; the test does the
            // same so the archived state still describes where the tab points.
            stateful.url = secondURL

            pool.select(tab: other, space: space)
            _ = try await waitForActivePage(in: pool, at: other.url ?? secondURL)
            pool.unloadPage(for: stateful.id)
            XCTAssertFalse(pool.containsResidentPage(for: stateful.id))
            await archive.flushPendingWrites()

            pool.select(tab: stateful, space: space)
            let restoredPage = try XCTUnwrap(pool.activePage)
            XCTAssertFalse(restoredPage === originalPage)
            XCTAssertEqual(
                restoredPage.webView.backForwardList.backList.map(\.url),
                [firstURL],
                "A restored tab must come back with the back/forward list it had."
            )
            restoredPage.webView.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
            _ = try await waitForActivePage(in: pool, at: secondURL)
            try await waitUntil("the restored scroll offset") {
                try await self.scrollOffset(of: restoredPage.webView) == scrolledOffset
            }
        } catch {
            pool.reconcile(validTabIDs: [])
            await removeDataStore(profile.id)
            throw error
        }

        pool.reconcile(validTabIDs: [])
        await removeDataStore(profile.id)
    }

    func testAPrivatePoolArchivesNothingWhereAStandardPoolArchivesState() async throws {
        let serverURL = try await requireNetworkFixture()
        let runID = UUID().uuidString
        let url = try fixtureURL(serverURL, run: runID, tab: 1)
        let stateful = BrowserTab(title: "Stateful", url: url, placement: .current)
        let other = BrowserTab(
            title: "Other",
            url: try fixtureURL(serverURL, run: runID, tab: 2),
            placement: .current
        )
        let standardProfile = BrowsingProfile()
        let privateProfile = BrowsingProfile()
        let standardSpace = makeSpace(profile: standardProfile, tabs: [stateful, other])
        let privateSpace = makeSpace(profile: privateProfile, tabs: [stateful, other])
        let standardArchive = try makeTabStateArchive()
        let privateArchive = try makeTabStateArchive()
        let standardPool = BrowserPagePool(
            tabStateArchive: standardArchive
        )
        let privatePool = BrowserPagePool(
            browsingMode: .privateBrowsing,
            tabStateArchive: privateArchive
        )

        do {
            for (pool, space) in [
                (standardPool, standardSpace),
                (privatePool, privateSpace),
            ] {
                pool.select(tab: stateful, space: space)
                _ = try await waitForActivePage(in: pool, at: url)
                pool.select(tab: other, space: space)
                _ = try await waitForActivePage(in: pool, at: other.url ?? url)
                pool.unloadPage(for: stateful.id)
            }
            await standardArchive.flushPendingWrites()
            await privateArchive.flushPendingWrites()

            XCTAssertNotNil(
                standardArchive.archivedState(
                    profileID: standardProfile.id,
                    tabID: stateful.id
                ),
                "The same idle unload must archive state for a standard Space."
            )
            XCTAssertNil(
                privateArchive.archivedState(
                    profileID: privateProfile.id,
                    tabID: stateful.id
                ),
                "Private browsing must leave nothing on disk to restore."
            )
        } catch {
            standardPool.reconcile(validTabIDs: [])
            privatePool.reconcile(validTabIDs: [])
            await removeDataStore(standardProfile.id)
            throw error
        }

        standardPool.reconcile(validTabIDs: [])
        privatePool.reconcile(validTabIDs: [])
        await removeDataStore(standardProfile.id)
    }

    func testServiceWorkerCachedNavigationSurvivesItsOriginGoingOffline() async throws {
        let fixtureURL = URL(
            string: ProcessInfo.processInfo.environment["CREST_OFFLINE_FIXTURE_URL"]
                ?? "http://127.0.0.1:18766/offline.html"
        )!
        let fixtureIsAvailable: Bool
        do {
            var probe = URLRequest(url: fixtureURL)
            probe.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            probe.timeoutInterval = 0.2
            probe.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: probe)
            fixtureIsAvailable =
                (response as? HTTPURLResponse)?.statusCode == 200
                && String(decoding: data, as: UTF8.self).contains("offline-marker")
        } catch {
            fixtureIsAvailable = false
        }
        guard fixtureIsAvailable else {
            throw XCTSkip("The checked-in offline fixture server is unavailable.")
        }
        let profile = BrowsingProfile()
        let webView = WKWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(for: profile)
        )
        let waiter = NavigationWaiter(webView: webView)

        do {
            try await waiter.load(URLRequest(url: fixtureURL))
            let registrationState = try await stringResult(
                from: webView,
                script: """
                    const registration = await navigator.serviceWorker.register('service-worker.js');
                    const ready = await Promise.race([
                        navigator.serviceWorker.ready,
                        new Promise((_, reject) => setTimeout(
                            () => reject(new Error('service-worker-timeout')),
                            5000
                        ))
                    ]);
                    const worker = ready.active ?? registration.active
                        ?? registration.installing ?? registration.waiting;
                    if (worker && worker.state !== 'activated') {
                        await Promise.race([
                            new Promise(resolve => worker.addEventListener(
                                'statechange',
                                () => worker.state === 'activated' && resolve(),
                                { once: false }
                            )),
                            new Promise((_, reject) => setTimeout(
                                () => reject(new Error('activation-timeout')),
                                5000
                            ))
                        ]);
                    }
                    return worker?.state ?? 'missing';
                    """
            )
            XCTAssertEqual(registrationState, "activated")

            try await waiter.reload()
            let isControlled = try await boolResult(
                from: webView,
                script: "return navigator.serviceWorker.controller !== null;"
            )
            XCTAssertTrue(isControlled)

            try await stopOfflineFixtureServer(at: fixtureURL)
            try await waitForOfflineFixtureServerToStop(at: fixtureURL)
            try await waiter.reload()

            let offlineMarker = try await stringResult(
                from: webView,
                script: "return document.querySelector('#offline-marker')?.textContent ?? '';"
            )
            XCTAssertEqual(offlineMarker, "Loaded from Crest's offline cache")
            XCTAssertEqual(webView.url, fixtureURL)
        } catch {
            await removeDataStore(profile.id)
            throw error
        }

        await removeDataStore(profile.id)
    }

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

    func testProductionWebPageRunsRepresentativeModernWebPlatformFeatures() async throws {
        let profile = BrowsingProfile()
        let webView = WKWebView(frame: .zero, configuration: BrowserPageConfiguration.make(for: profile))

        try await loadFixture(on: webView, origin: URL(string: "https://compat.crest.test/")!)
        let capabilities = try await jsonResult(
            from: webView,
            script: """
                const video = document.createElement('video');
                const audio = document.createElement('audio');
                const canvas = document.createElement('canvas');
                const wasmResult = await WebAssembly.instantiate(
                    new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0])
                );
                const digest = await crypto.subtle.digest(
                    'SHA-256',
                    new TextEncoder().encode('crest')
                );
                const workerRoundTrip = await new Promise(resolve => {
                    const source = new Blob(
                        ['onmessage = event => postMessage(`worker-${event.data}`)'],
                        { type: 'text/javascript' }
                    );
                    const sourceURL = URL.createObjectURL(source);
                    const worker = new Worker(sourceURL);
                    const timeout = setTimeout(() => resolve(false), 2000);
                    worker.onmessage = event => {
                        clearTimeout(timeout);
                        worker.terminate();
                        URL.revokeObjectURL(sourceURL);
                        resolve(event.data === 'worker-ready');
                    };
                    worker.postMessage('ready');
                });
                const channelName = `crest-${crypto.randomUUID()}`;
                const channelA = new BroadcastChannel(channelName);
                const channelB = new BroadcastChannel(channelName);
                const broadcastChannelRoundTrip = await new Promise(resolve => {
                    const timeout = setTimeout(() => resolve(false), 2000);
                    channelB.onmessage = event => {
                        clearTimeout(timeout);
                        resolve(event.data === 'channel-ready');
                    };
                    channelA.postMessage('channel-ready');
                });
                channelA.close();
                channelB.close();

                class CrestProbeElement extends HTMLElement {
                    connectedCallback() {
                        this.dataset.connected = 'true';
                        this.attachShadow({ mode: 'open' }).innerHTML = '<span>shadow-ready</span>';
                    }
                }
                customElements.define('crest-compatibility-probe', CrestProbeElement);
                const customElement = document.createElement('crest-compatibility-probe');
                document.body.append(customElement);

                let compressionRoundTrip = false;
                if (typeof CompressionStream === 'function' && typeof DecompressionStream === 'function') {
                    const stream = new Blob(['compressed-ready']).stream()
                        .pipeThrough(new CompressionStream('gzip'))
                        .pipeThrough(new DecompressionStream('gzip'));
                    compressionRoundTrip = await new Response(stream).text() === 'compressed-ready';
                }

                let offlineAudioRoundTrip = false;
                if (typeof OfflineAudioContext === 'function') {
                    const audioContext = new OfflineAudioContext(1, 128, 44100);
                    const oscillator = new OscillatorNode(audioContext);
                    oscillator.connect(audioContext.destination);
                    oscillator.start();
                    const rendered = await audioContext.startRendering();
                    offlineAudioRoundTrip = rendered.length === 128 && rendered.numberOfChannels === 1;
                }

                return JSON.stringify({
                    domMutation: document.querySelector('#status').textContent === 'ready',
                    cssLayout: getComputedStyle(document.querySelector('#status')).display === 'grid',
                    fetch: typeof fetch === 'function',
                    webSocket: typeof WebSocket === 'function',
                    eventSource: typeof EventSource === 'function',
                    worker: typeof Worker === 'function',
                    sharedWorker: typeof SharedWorker === 'function',
                    serviceWorker: 'serviceWorker' in navigator,
                    indexedDB: typeof indexedDB === 'object',
                    webAssembly: typeof WebAssembly === 'object',
                    webAssemblyRoundTrip: wasmResult.instance instanceof WebAssembly.Instance,
                    webCrypto: !!(crypto && crypto.subtle),
                    webCryptoRoundTrip: digest.byteLength === 32,
                    workerRoundTrip,
                    broadcastChannelRoundTrip,
                    customElementRoundTrip: customElement.dataset.connected === 'true'
                        && customElement.shadowRoot?.textContent === 'shadow-ready',
                    compressionRoundTrip,
                    offlineAudioRoundTrip,
                    canvas2D: !!canvas.getContext('2d'),
                    webGLAPI: typeof WebGLRenderingContext === 'function',
                    webGL2API: typeof WebGL2RenderingContext === 'function',
                    webGL: !!canvas.getContext('webgl'),
                    webGL2: !!canvas.getContext('webgl2'),
                    webGPU: !!navigator.gpu,
                    h264: video.canPlayType('video/mp4; codecs="avc1.42E01E"') !== '',
                    hls: video.canPlayType('application/vnd.apple.mpegurl') !== '',
                    aac: audio.canPlayType('audio/mp4; codecs="mp4a.40.2"') !== '',
                    mediaSource: typeof MediaSource === 'function',
                    encryptedMedia: typeof navigator.requestMediaKeySystemAccess === 'function',
                    fullscreen: typeof document.documentElement.requestFullscreen === 'function',
                    pictureInPicture: typeof video.requestPictureInPicture === 'function',
                    fileInput: document.querySelector('#files').multiple,
                    downloadAttribute: 'download' in document.createElement('a')
                });
                """
        )

        let requiredCapabilities = [
            "domMutation", "cssLayout", "fetch", "webSocket", "eventSource", "worker",
            "sharedWorker", "serviceWorker", "indexedDB", "webAssembly", "webCrypto",
            "webAssemblyRoundTrip", "webCryptoRoundTrip", "workerRoundTrip",
            "broadcastChannelRoundTrip", "customElementRoundTrip", "compressionRoundTrip",
            "offlineAudioRoundTrip", "canvas2D", "webGLAPI", "webGL2API", "h264", "hls",
            "aac", "mediaSource", "encryptedMedia", "pictureInPicture", "fileInput",
            "downloadAttribute",
        ]
        for capability in requiredCapabilities {
            XCTAssertEqual(capabilities[capability] as? Bool, true, "Missing web capability: \(capability)")
        }

        // GPU-backed contexts and element fullscreen need an attached, rendered WebView. Record
        // them here, then require them in the live UI corpus rather than treating test-host
        // sandbox limitations as browser support failures.
        for runtimeCapability in ["webGL", "webGL2", "webGPU", "fullscreen"] {
            XCTAssertNotNil(capabilities[runtimeCapability] as? Bool)
        }
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
            ),
            selectedTabID: openerTab.id
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pool = BrowserPagePool(
            popupTabHost: store.popupTabHost
        )

        do {
            pool.select(session: store.session)
            let opener = try XCTUnwrap(pool.activePage)
            opener.webView.loadSimulatedRequest(
                URLRequest(url: origin),
                responseHTML: fixtureHTML
            )
            try await waitUntil("the opener fixture to load") {
                opener.url == origin && !opener.isLoading
            }
            // `window.open()` is scripted, so it answers to the site's pop-up
            // permission rather than to a user gesture.
            pool.permissionCenter.setDecision(
                .grantPersistently,
                for: .popups,
                origin: try XCTUnwrap(BrowserSiteOrigin(url: origin)),
                in: space.id
            )

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
                "window.open() must hand the page a real window."
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

    /// The checked-in performance corpus, or a skip when its server is not running.
    private func requireNetworkFixture() async throws -> URL {
        let serverURL = URL(
            string: ProcessInfo.processInfo.environment["CREST_NETWORK_FIXTURE_URL"]
                ?? "http://127.0.0.1:18768/"
        )!
        guard let metrics = try? await networkFixtureMetrics(at: serverURL),
            metrics.server == "crest-network-fixture-v1"
        else {
            throw XCTSkip("The checked-in network fixture server is unavailable.")
        }
        return serverURL
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
            ),
            selectedTabID: tabs.first?.id
        )
    }

    private func makeTabStateArchive() throws -> BrowserTabStateArchive {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "crest-web-tab-state-\(UUID().uuidString)",
                isDirectory: true
            )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return BrowserTabStateArchive(rootDirectory: root)
    }

    private func scrollOffset(of page: WKWebView) async throws -> Double {
        let value = try await page.callAsyncJavaScript(
            "return window.scrollY;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(value as? Double ?? (value as? NSNumber)?.doubleValue)
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

    private func stopOfflineFixtureServer(at fixtureURL: URL) async throws {
        let stopURL = try XCTUnwrap(
            URL(string: "/__crest_stop__", relativeTo: fixtureURL)?.absoluteURL
        )
        var request = URLRequest(url: stopURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    private func waitForOfflineFixtureServerToStop(at fixtureURL: URL) async throws {
        for attempt in 0..<40 {
            var request = URLRequest(url: fixtureURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 0.2
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                return
            }
            if attempt < 39 {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        XCTFail("The offline fixture origin remained reachable after shutdown.")
    }

    private func networkFixtureMetrics(at serverURL: URL) async throws -> NetworkFixtureMetrics {
        let metricsURL = try XCTUnwrap(
            URL(string: "/__crest_network_metrics__", relativeTo: serverURL)?.absoluteURL
        )
        var request = URLRequest(url: metricsURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 0.5
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONDecoder().decode(NetworkFixtureMetrics.self, from: data)
    }

    private func resetNetworkFixtureMetrics(at serverURL: URL) async throws {
        let resetURL = try XCTUnwrap(
            URL(string: "/__crest_network_reset__", relativeTo: serverURL)?.absoluteURL
        )
        var request = URLRequest(url: resetURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 0.5
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
    }

    private func waitForActivePage(
        in pool: BrowserPagePool,
        at expectedURL: URL
    ) async throws -> BrowserPage {
        for attempt in 0..<120 {
            if let page = pool.activePage,
                page.url == expectedURL,
                !page.isLoading
            {
                return page
            }
            if attempt < 119 {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        throw NetworkFixtureTestError.navigationTimedOut(expectedURL)
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

private struct NetworkFixtureMetrics: Decodable {
    let server: String
    let requests: [String: Int]

    /// Every counted request except WebKit's own favicon fetches.
    ///
    /// What these tests pin is when Crest reloads a *page*: a resident page must
    /// refetch nothing, an idle-unloaded one must refetch once. WebKit fetches
    /// `/favicon.ico` on a schedule of its own — per web-content process, after
    /// a document commits, and with no bound this side can settle for — so a
    /// whole-dictionary comparison turns a page-resource assertion into a race
    /// with the icon fetcher. Dropping the icon keeps the assertion on exactly
    /// the counts the page is responsible for.
    var pageResourceRequests: [String: Int] {
        requests.filter { target, _ in
            let path = target.prefix { $0 != "?" }
            return !path.hasSuffix("/favicon.ico")
        }
    }
}

private enum NetworkFixtureTestError: Error {
    case navigationTimedOut(URL)
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
