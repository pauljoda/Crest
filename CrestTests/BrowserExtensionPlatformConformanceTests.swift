import AppKit
import WebKit
import XCTest

@testable import Crest

/// Covers the WebExtension platform surface Crest promises WebKit: the optional
/// adapter methods it implements, the delegate callbacks it answers, and the
/// tab metadata it is allowed to reveal.
@MainActor
final class BrowserExtensionPlatformConformanceTests: XCTestCase {
    private final class PageProviderStub: BrowserExtensionPageProviding {
        var webViews: [TabID: WKWebView] = [:]
        var readerModeStates: [TabID: BrowserReaderModeState] = [:]
        var windowGeometry = BrowserExtensionWindowGeometry.unavailable
        private(set) var readerModeRequests: [(TabID, Bool)] = []

        func extensionWebView(
            for tabID: TabID,
            in spaceID: SpaceID
        ) -> WKWebView? {
            webViews[tabID]
        }

        func extensionReaderModeState(
            for tabID: TabID,
            in spaceID: SpaceID
        ) -> BrowserReaderModeState {
            readerModeStates[tabID] ?? .unavailable
        }

        func setExtensionReaderModeActive(
            _ isActive: Bool,
            for tabID: TabID,
            in spaceID: SpaceID
        ) async throws {
            readerModeRequests.append((tabID, isActive))
            readerModeStates[tabID] = isActive ? .active : .available
        }

        func extensionWindowGeometry(
            in spaceID: SpaceID
        ) -> BrowserExtensionWindowGeometry {
            windowGeometry
        }

        func prepareExtensionSelection(session: BrowserSession) {}

        func select(session: BrowserSession) {}
    }

    // MARK: - Selector conformance

    /// A Swift method that only *nearly* matches an optional WebKit requirement
    /// compiles without complaint and is then never called, so each one Crest
    /// relies on is pinned by its Objective-C selector.
    func testTabAdapterAnswersEveryOptionalTabSelectorCrestImplements()
        async throws
    {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderStub())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        _ = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        let tab = try XCTUnwrap(space.tabs.first)
        let adapter = try XCTUnwrap(pool.extensionTab(tab.id, in: space.id))

        for name in [
            "sizeForWebExtensionContext:",
            "isLoadingCompleteForWebExtensionContext:",
            "isReaderModeAvailableForWebExtensionContext:",
            "isReaderModeActiveForWebExtensionContext:",
            "setReaderModeActive:forWebExtensionContext:completionHandler:",
            "detectWebpageLocaleForWebExtensionContext:completionHandler:",
            "takeSnapshotUsingConfiguration:forWebExtensionContext:completionHandler:",
        ] {
            XCTAssertTrue(
                adapter.responds(to: NSSelectorFromString(name)),
                "The tab adapter no longer matches \(name)."
            )
        }
    }

    func testWindowAdapterAnswersTheGeometrySelectors() async throws {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderStub())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        _ = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        let window = try XCTUnwrap(pool.extensionWindow(in: space.id))

        for name in [
            "frameForWebExtensionContext:",
            "screenFrameForWebExtensionContext:",
            "windowStateForWebExtensionContext:",
        ] {
            XCTAssertTrue(
                window.responds(to: NSSelectorFromString(name)),
                "The window adapter no longer matches \(name)."
            )
        }
    }

    func testCoordinatorAnswersTheOptionsPageDelegateSelector() {
        let coordinator = BrowserExtensionControllerPool()
            .tabWindowCoordinator

        XCTAssertTrue(
            coordinator.responds(
                to: NSSelectorFromString(
                    "webExtensionController:openOptionsPageForExtensionContext:completionHandler:"
                )
            )
        )
    }

    // MARK: - Tab metadata

    func testStartPageTitleStaysHiddenWithoutTheTabsPermission() async throws {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderStub())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        let startPage = try XCTUnwrap(
            space.tabs.first(where: { $0.url == nil })
        )
        let adapter = try XCTUnwrap(
            pool.extensionTab(startPage.id, in: space.id)
        )

        // A tab with no URL offers no host to match, so only the tabs
        // permission can justify revealing what the person named it.
        XCTAssertNil(adapter.title(for: context))
        XCTAssertNil(adapter.url(for: context))

        context.setPermissionStatus(.grantedExplicitly, for: .tabs)

        XCTAssertEqual(adapter.title(for: context), startPage.title)
    }

    // MARK: - Runtime activity

    func testSessionProjectionCarriesLoadingAndReaderModeActivity() throws {
        let session = BrowserSession.preview
        let space = try XCTUnwrap(session.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)

        let settled = BrowserExtensionSessionState(session: session)
        let busy = BrowserExtensionSessionState(session: session) {
            _, tabID in
            BrowserExtensionTabRuntimeActivity(
                isLoadingComplete: tabID != tab.id,
                isReaderModeActive: tabID == tab.id
            )
        }

        XCTAssertEqual(settled.space(space.id)?.tab(tab.id)?.isLoadingComplete, true)
        XCTAssertEqual(
            settled.space(space.id)?.tab(tab.id)?.isReaderModeActive,
            false
        )
        XCTAssertEqual(busy.space(space.id)?.tab(tab.id)?.isLoadingComplete, false)
        XCTAssertEqual(
            busy.space(space.id)?.tab(tab.id)?.isReaderModeActive,
            true
        )
        XCTAssertNotEqual(settled, busy)
    }

    func testTabAdapterReportsAndTogglesReaderMode() async throws {
        let browser = BrowserStore.preview()
        let pages = PageProviderStub()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: pages)
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        let tab = try XCTUnwrap(space.tabs.first)
        let adapter = try XCTUnwrap(pool.extensionTab(tab.id, in: space.id))

        XCTAssertFalse(adapter.isReaderModeAvailable(for: context))
        XCTAssertFalse(adapter.isReaderModeActive(for: context))

        pages.readerModeStates[tab.id] = .available

        XCTAssertTrue(adapter.isReaderModeAvailable(for: context))
        XCTAssertFalse(adapter.isReaderModeActive(for: context))

        let activated = expectation(description: "reader mode activated")
        var activationError: Error?
        adapter.setReaderModeActive(true, for: context) { error in
            activationError = error
            activated.fulfill()
        }
        await fulfillment(of: [activated], timeout: 5)

        XCTAssertNil(activationError)
        XCTAssertEqual(pages.readerModeRequests.count, 1)
        XCTAssertEqual(pages.readerModeRequests.first?.1, true)
        XCTAssertTrue(adapter.isReaderModeActive(for: context))
    }

    func testWindowAdapterReportsTheHostingWindowGeometry() async throws {
        let browser = BrowserStore.preview()
        let pages = PageProviderStub()
        let frame = CGRect(x: 12, y: 34, width: 900, height: 600)
        let screenFrame = CGRect(x: 0, y: 0, width: 1_800, height: 1_200)
        pages.windowGeometry = BrowserExtensionWindowGeometry(
            frame: frame,
            screenFrame: screenFrame,
            state: .fullscreen
        )
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: pages)
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        let window = try XCTUnwrap(pool.extensionWindow(in: space.id))

        XCTAssertEqual(window.frame(for: context), frame)
        XCTAssertEqual(window.screenFrame(for: context), screenFrame)
        XCTAssertEqual(window.windowState(for: context), .fullscreen)
    }

    // MARK: - Options page

    func testOptionsPageFocusesAnOpenTabInsteadOfOpeningASecond() async throws {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderStub())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        let optionsURL = try XCTUnwrap(context.optionsPageURL)
        let originalCount = try XCTUnwrap(
            browser.session.space(id: space.id)?.tabs.count
        )

        pool.openOptionsPage(extensionID: extensionID, in: space.id)
        let afterFirst = try XCTUnwrap(
            browser.session.space(id: space.id)?.tabs.count
        )
        pool.openOptionsPage(extensionID: extensionID, in: space.id)
        let afterSecond = try XCTUnwrap(
            browser.session.space(id: space.id)?.tabs.count
        )

        XCTAssertEqual(afterFirst, originalCount + 1)
        XCTAssertEqual(afterSecond, afterFirst)
        XCTAssertEqual(browser.session.selectedTab?.url, optionsURL)
    }

    func testOptionsPageDelegateReportsAMissingOptionsPage() async throws {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderStub())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let extensionURL = try makeTemporaryExtension(
            named: "No Options",
            extraManifest: [:]
        )
        defer { try? FileManager.default.removeItem(at: extensionURL) }
        let context = try await pool.loadExtension(
            at: extensionURL,
            extensionID: "com.example.no-options",
            in: space
        )
        let controller = pool.controller(for: space)
        var reported: Error?

        pool.tabWindowCoordinator.webExtensionController(
            controller,
            openOptionsPageFor: context
        ) { reported = $0 }

        XCTAssertEqual(
            (reported as? NSError)?.code,
            BrowserExtensionAdapterErrorCode.optionsPageUnavailable.rawValue
        )
    }

    // MARK: - Commands

    func testMatchingKeyboardCommandGrantsTheActiveTabGesture() async throws {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderStub())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        pool.reconcileExtensionState(in: browser.session)
        let selectedID = try XCTUnwrap(browser.session.selectedTab?.id)
        let adapter = try XCTUnwrap(pool.extensionTab(selectedID, in: space.id))

        XCTAssertFalse(context.hasActiveUserGesture(in: adapter))

        _ = pool.performCommand(
            for: try XCTUnwrap(
                keyEvent(character: "b", modifiers: [.option, .shift])
            ),
            in: space.id
        )

        // An unrelated keystroke must not hand out activeTab.
        XCTAssertFalse(context.hasActiveUserGesture(in: adapter))

        _ = pool.performCommand(
            for: try XCTUnwrap(
                keyEvent(character: "a", modifiers: [.option, .shift])
            ),
            in: space.id
        )

        XCTAssertTrue(context.hasActiveUserGesture(in: adapter))
    }

    // MARK: - Context menu

    func testTabMenuAPIDoesNotExposeWebpageContextItems()
        async throws
    {
        let origin = try XCTUnwrap(
            URL(string: "https://context-menu.crest.test/image")
        )
        let tab = BrowserTab(
            title: "Context Menu Probe",
            url: origin,
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Context Menu Probe",
            symbol: "photo",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pool = BrowserExtensionControllerPool()
        let controller = pool.controller(for: space)
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 320),
            configuration: BrowserPageConfiguration.make(
                for: space.profile,
                webExtensionController: controller
            )
        )
        let pages = PageProviderStub()
        pages.webViews[tab.id] = webView
        pool.connect(browser: browser, pageProvider: pages)

        let extensionURL = try makeContextMenuExtension()
        defer { try? FileManager.default.removeItem(at: extensionURL) }
        let context = try await pool.loadExtension(
            at: extensionURL,
            extensionID: "com.pauldavis.crest.context-menu-probe",
            in: space
        )
        context.setPermissionStatus(.grantedExplicitly, for: .contextMenus)
        context.setPermissionStatus(.grantedExplicitly, for: origin)
        pool.reconcileExtensionState(in: browser.session)
        let adapter = try XCTUnwrap(
            pool.extensionTab(tab.id, in: space.id)
        )

        var registeredTabTitles: [String] = []
        for _ in 0..<400 {
            registeredTabTitles = context.menuItems(for: adapter).map(\.title)
            if registeredTabTitles.contains("Probe Tab") { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(
            registeredTabTitles.contains("Probe Tab"),
            "The extension background did not finish registering its menus."
        )
        XCTAssertFalse(registeredTabTitles.contains("Probe Image"))
        XCTAssertFalse(registeredTabTitles.contains("Probe Page"))
    }

    func testContextMenuTransportPermissionIsInternalToPreparedExtensions()
        async throws
    {
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let sourceURL = try makeContextMenuExtension()
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let runtimeIdentity = BrowserExtensionRuntimeIdentity(
            extensionID: extensionID.rawValue,
            uniqueIdentifier: "context-menu-transport-test",
            baseURL: try XCTUnwrap(
                URL(string: "crest-extension://context-menu-transport-test/")
            )
        )
        let prepared = try XCTUnwrap(
            BrowserWebExtensionCompatibilityPackagePreparer()
                .prepareStoredResource(
                    sourceURL,
                    requestedPermissions: ["contextMenus"],
                    runtimeIdentity: runtimeIdentity
                )
        )
        let preparedManifestData = try Data(
            contentsOf: prepared.resourceURL.appending(path: "manifest.json")
        )
        let preparedManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: preparedManifestData)
                as? [String: Any]
        )
        let preparedPermissions = try XCTUnwrap(
            preparedManifest["permissions"] as? [String]
        )
        // The transport is a host grant, not an authored permission, and the
        // package manifest is left alone: writing `nativeMessaging` into it
        // would let an extension light up an optional native-companion path
        // solely because Crest needs private transport. The grant is applied
        // to the loaded context instead.
        XCTAssertFalse(preparedPermissions.contains("nativeMessaging"))
        XCTAssertEqual(
            prepared.internalGrantedPermissions,
            ["nativeMessaging"]
        )

        let source = BrowserExtensionInstallationSource.chromeWebStore(
            BrowserChromeWebStoreSource(
                extensionID: extensionID,
                storeURL: try XCTUnwrap(
                    URL(
                        string:
                            "https://chromewebstore.google.com/detail/test/\(extensionID.rawValue)"
                    )
                ),
                crxSHA256Hex: String(repeating: "a", count: 64),
                publisherKeyHashHex: String(repeating: "b", count: 64)
            )
        )
        let space = BrowserSession.preview.spaces[0]
        let webpageMenuRegistry = BrowserExtensionWebpageMenuRegistry()
        let pool = BrowserExtensionControllerPool(
            webpageMenuRegistry: webpageMenuRegistry
        )
        pool.setNativeMessagingHandler(
            BrowserNativeMessagingService(
                capability: .available,
                resolver: BrowserNativeMessagingHostManifestResolver(
                    searchDirectories: []
                ),
                webpageMenuRegistry: webpageMenuRegistry
            )
        )
        let context = try await pool.runtimeContextController.loadExtension(
            at: prepared.resourceURL,
            extensionID: extensionID.rawValue,
            in: space,
            unsupportedAPIs: [],
            permissionSnapshot:
                BrowserExtensionInstallationPermissionPolicy
                .reviewedRequiredAccess(
                    permissions: ["contextMenus"],
                    hosts: []
                ),
            persistsRuntimeSummary: false,
            source: source,
            internalGrantedPermissions: prepared.internalGrantedPermissions,
            // The install path hands the runtime these alongside the
            // internal grant: without them the capability broker refuses
            // the port, and no menu definition ever reaches the registry.
            capabilityBrokerGrantedPermissions:
                prepared.capabilityBrokerGrantedPermissions,
            allowsInternalCapabilityBroker:
                prepared.allowsInternalCapabilityBroker
        )
        let summary = pool.runtimeContextController.summary(
            for: context,
            extensionID: extensionID.rawValue,
            isEnabled: true
        )

        XCTAssertTrue(context.hasPermission(.nativeMessaging))
        XCTAssertTrue(summary.requestedPermissions.contains("contextMenus"))
        XCTAssertFalse(summary.requestedPermissions.contains("nativeMessaging"))
        XCTAssertNil(
            summary.permissionSnapshot.grantedPermissions["nativeMessaging"]
        )
        let clientID = BrowserExtensionServiceClientID.scoped(
            extensionID: extensionID.rawValue,
            spaceID: space.id
        )
        var definitions: [BrowserExtensionWebpageMenuDefinition] = []
        for _ in 0..<200 {
            definitions = webpageMenuRegistry.definitions(for: clientID)
            if definitions.count == 3 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(
            definitions.map(\.id),
            [
                "string:probe-tab",
                "string:probe-image",
                "string:probe-page",
            ])
        XCTAssertEqual(
            definitions.first { $0.id == "string:probe-image" }?.contexts,
            ["image"]
        )
        XCTAssertEqual(
            definitions.first { $0.id == "string:probe-page" }?.contexts,
            ["page"]
        )

        let tab = try XCTUnwrap(
            space.tabs.first { $0.id == space.selectedTabID }
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = PageProviderStub()
        pages.webViews[tab.id] = WKWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(
                for: space.profile,
                webExtensionController: pool.controller(for: space)
            )
        )
        pool.connect(browser: browser, pageProvider: pages)
        pool.reconcileExtensionState(in: browser.session)
        let adapter = try XCTUnwrap(
            pool.extensionTab(tab.id, in: space.id)
        )
        var nativeTitles: [String] = []
        for _ in 0..<200 {
            nativeTitles = context.menuItems(for: adapter).map(\.title)
            if nativeTitles.count == 3 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(nativeTitles, ["Context Menu Probe"])
        XCTAssertEqual(
            context.menuItems(for: adapter).first?.submenu?.items.map(\.title),
            ["Probe Tab", "Probe Image", "Probe Page"]
        )
        let toolbarActions = pool.toolbarController.toolbarActions(
            summaries: [summary],
            in: space.id,
            tabID: tab.id
        )
        XCTAssertEqual(
            toolbarActions.first?.menuItems.map(\.title),
            ["Probe Tab"]
        )

        let provider = BrowserExtensionWebpageMenuProvider(
            extensionControllerPool: pool
        )
        // A source URL alone is not a media context. The hit-test result
        // reports the media kind separately, and the live capture carries it
        // through `BrowserLinkContext.mediaType`, so a click on an image has
        // to say so here too — otherwise this is a plain `page` click and the
        // page items are the correct answer.
        let imageContext = BrowserExtensionWebpageMenuContext(
            pageURL: try XCTUnwrap(URL(string: "https://example.com/page")),
            documentURL: try XCTUnwrap(URL(string: "https://example.com/page")),
            linkURL: nil,
            sourceURL: try XCTUnwrap(
                URL(string: "https://example.com/photo.webp")
            ),
            mediaType: .image,
            selectionText: nil,
            isEditable: false,
            isMainFrame: true
        )
        let imageItems = provider.items(
            for: tab.id,
            in: space.id,
            context: imageContext
        )
        XCTAssertEqual(imageItems.map(\.title), ["Probe Image"])
        let imageItem = try XCTUnwrap(imageItems.first)
        var publishedItemID: String?
        _ = webpageMenuRegistry.observeClicks(for: clientID) { message in
            publishedItemID = message["menuItemID"] as? String
        }
        XCTAssertTrue(
            NSApp.sendAction(
                try XCTUnwrap(imageItem.action),
                to: imageItem.target,
                from: imageItem
            )
        )
        XCTAssertEqual(publishedItemID, "string:probe-image")
        XCTAssertTrue(context.hasActiveUserGesture(in: adapter))
    }

    func testLocalContextMenuExtensionReachesTheInternalBroker()
        async throws
    {
        let extensionID = "context-menu-local-probe@example.com"
        let sourceURL = try makeContextMenuExtension()
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let prepared = try XCTUnwrap(
            BrowserWebExtensionCompatibilityPackagePreparer()
                .prepareStoredResource(
                    sourceURL,
                    requestedPermissions: ["contextMenus"],
                    runtimeIdentity:
                        BrowserExtensionRuntimeIdentifierPolicy
                        .identity(
                            extensionID: extensionID,
                            source: .localPackage(
                                BrowserLocalExtensionSource(
                                    extensionID: extensionID,
                                    format: .firefoxXPI,
                                    sha256Hex: String(repeating: "a", count: 64)
                                )
                            ),
                            spaceID: BrowserSession.preview.spaces[0].id
                        )
                )
        )
        let source = BrowserExtensionInstallationSource.localPackage(
            BrowserLocalExtensionSource(
                extensionID: extensionID,
                format: .firefoxXPI,
                sha256Hex: String(repeating: "a", count: 64)
            )
        )
        let space = BrowserSession.preview.spaces[0]
        let registry = BrowserExtensionWebpageMenuRegistry()
        let pool = BrowserExtensionControllerPool(
            webpageMenuRegistry: registry
        )
        pool.setNativeMessagingHandler(
            BrowserNativeMessagingService(
                capability: .available,
                resolver: BrowserNativeMessagingHostManifestResolver(
                    searchDirectories: []
                ),
                webpageMenuRegistry: registry
            )
        )

        _ = try await pool.runtimeContextController.loadExtension(
            at: prepared.resourceURL,
            extensionID: extensionID,
            in: space,
            unsupportedAPIs: [],
            permissionSnapshot:
                BrowserExtensionInstallationPermissionPolicy
                .reviewedRequiredAccess(
                    permissions: ["contextMenus"],
                    hosts: []
                ),
            persistsRuntimeSummary: false,
            source: source,
            internalGrantedPermissions: prepared.internalGrantedPermissions,
            // The install path hands the runtime these alongside the
            // internal grant: without them the capability broker refuses
            // the port, and no menu definition ever reaches the registry.
            capabilityBrokerGrantedPermissions:
                prepared.capabilityBrokerGrantedPermissions,
            allowsInternalCapabilityBroker:
                prepared.allowsInternalCapabilityBroker
        )

        let clientID = BrowserExtensionServiceClientID.scoped(
            extensionID: extensionID,
            spaceID: space.id
        )
        for _ in 0..<200 {
            if !registry.definitions(for: clientID).isEmpty { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(registry.definitions(for: clientID).isEmpty)
    }

    func testPreparedContextMenuFixtureFiltersNativeWebpageItemsAndPreservesTree()
        async throws
    {
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "bcdefghijklmnopabcdefghijklmnopa"
            )
        )
        let runtimeIdentity = BrowserExtensionRuntimeIdentity(
            extensionID: extensionID.rawValue,
            uniqueIdentifier: "context-menu-fixture-test",
            baseURL: try XCTUnwrap(
                URL(string: "crest-extension://context-menu-fixture-test/")
            )
        )
        let prepared = try XCTUnwrap(
            BrowserWebExtensionCompatibilityPackagePreparer()
                .prepareStoredResource(
                    contextMenusFixtureURL,
                    requestedPermissions: ["contextMenus", "tabs"],
                    runtimeIdentity: runtimeIdentity
                )
        )
        let pageURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:8765/context-menu.html")
        )
        let tab = BrowserTab(
            title: "Context Menu Fixture",
            url: pageURL,
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Context Menu Fixture",
            symbol: "cursorarrow.click",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let registry = BrowserExtensionWebpageMenuRegistry()
        let pool = BrowserExtensionControllerPool(
            webpageMenuRegistry: registry
        )
        pool.setNativeMessagingHandler(
            BrowserNativeMessagingService(
                capability: .available,
                resolver: BrowserNativeMessagingHostManifestResolver(
                    searchDirectories: []
                ),
                webpageMenuRegistry: registry
            )
        )
        let pages = PageProviderStub()
        pages.webViews[tab.id] = WKWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(
                for: space.profile,
                webExtensionController: pool.controller(for: space)
            )
        )
        pool.connect(browser: browser, pageProvider: pages)
        let source = BrowserExtensionInstallationSource.chromeWebStore(
            BrowserChromeWebStoreSource(
                extensionID: extensionID,
                storeURL: try XCTUnwrap(
                    URL(
                        string:
                            "https://chromewebstore.google.com/detail/fixture/\(extensionID.rawValue)"
                    )
                ),
                crxSHA256Hex: String(repeating: "c", count: 64),
                publisherKeyHashHex: String(repeating: "d", count: 64)
            )
        )
        let context = try await pool.runtimeContextController.loadExtension(
            at: prepared.resourceURL,
            extensionID: extensionID.rawValue,
            in: space,
            unsupportedAPIs: [],
            permissionSnapshot:
                BrowserExtensionInstallationPermissionPolicy
                .reviewedRequiredAccess(
                    permissions: ["contextMenus", "tabs"],
                    hosts: ["http://127.0.0.1/*"]
                ),
            persistsRuntimeSummary: false,
            source: source,
            internalGrantedPermissions: prepared.internalGrantedPermissions,
            // The install path hands the runtime these alongside the
            // internal grant: without them the capability broker refuses
            // the port, and no menu definition ever reaches the registry.
            capabilityBrokerGrantedPermissions:
                prepared.capabilityBrokerGrantedPermissions,
            allowsInternalCapabilityBroker:
                prepared.allowsInternalCapabilityBroker
        )
        pool.reconcileExtensionState(in: browser.session)
        let adapter = try XCTUnwrap(
            pool.extensionTab(tab.id, in: space.id)
        )
        let clientID = BrowserExtensionServiceClientID.scoped(
            extensionID: extensionID.rawValue,
            spaceID: space.id
        )
        var definitions: [BrowserExtensionWebpageMenuDefinition] = []
        for _ in 0..<200 {
            definitions = registry.definitions(for: clientID)
            if definitions.count == 14 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(definitions.count, 14)

        var nativeItems: [NSMenuItem] = []
        for _ in 0..<200 {
            nativeItems = context.menuItems(for: adapter)
            if nativeItems.first?.submenu?.items.count == 11 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let mapped = try BrowserExtensionWebpageMenuPolicy.nativeItems(
            nativeItems,
            definitions: definitions
        )
        XCTAssertEqual(mapped.count, 11)
        let nested = try XCTUnwrap(
            mapped.first { $0.definition.id == "string:nested" }
        )
        XCTAssertEqual(
            nested.children.map(\.definition.id),
            [
                "string:nested-image",
                "string:nested-separator",
                "string:nested-disabled",
            ]
        )
        XCTAssertTrue(nested.children[1].nativeItem.isSeparatorItem)

        let provider = BrowserExtensionWebpageMenuProvider(
            extensionControllerPool: pool
        )
        let imageItems = provider.items(
            for: tab.id,
            in: space.id,
            // See the image context above: the media kind is reported
            // separately from the source URL, so an image click has to
            // declare it.
            context: BrowserExtensionWebpageMenuContext(
                pageURL: pageURL,
                documentURL: pageURL,
                linkURL: nil,
                sourceURL: try XCTUnwrap(
                    URL(string: "http://127.0.0.1:8765/photo.webp")
                ),
                mediaType: .image,
                selectionText: nil,
                isEditable: false,
                isMainFrame: true
            )
        )
        let extensionGroup = try XCTUnwrap(imageItems.first)
        XCTAssertEqual(imageItems.map(\.title), ["Crest Context Menus Fixture"])
        XCTAssertEqual(
            extensionGroup.submenu?.items.map(\.title),
            ["Fixture Image", "Fixture Nested"]
        )
        let nestedGroup = try XCTUnwrap(
            extensionGroup.submenu?.items.last
        )
        XCTAssertEqual(
            nestedGroup.submenu?.items.map {
                $0.isSeparatorItem ? "-" : $0.title
            },
            ["Nested Image Action", "-", "Disabled Image Action"]
        )
        XCTAssertFalse(
            try XCTUnwrap(nestedGroup.submenu?.items.last).isEnabled
        )

        let frameItems = provider.items(
            for: tab.id,
            in: space.id,
            context: BrowserExtensionWebpageMenuContext(
                pageURL: pageURL,
                documentURL: try XCTUnwrap(
                    URL(string: "http://127.0.0.1:8765/frame.html")
                ),
                linkURL: nil,
                sourceURL: nil,
                selectionText: "chosen words",
                isEditable: true,
                isMainFrame: false
            )
        )
        XCTAssertEqual(
            frameItems.first?.submenu?.items.map(\.title),
            [
                "Fixture Selection: chosen words",
                "Fixture Editable",
                "Fixture Frame",
            ]
        )
        let enabledSummary = pool.runtimeContextController.summary(
            for: context,
            extensionID: extensionID.rawValue,
            isEnabled: true
        )
        let toolbarActions = pool.toolbarController.toolbarActions(
            summaries: [enabledSummary],
            in: space.id,
            tabID: tab.id
        )
        XCTAssertEqual(
            toolbarActions.first?.menuItems.map(\.title),
            ["Fixture Nested", "Fixture Tab"]
        )
        let disabledSummary = BrowserExtensionSummary(
            id: enabledSummary.id,
            displayName: enabledSummary.displayName,
            version: enabledSummary.version,
            requestedPermissions: enabledSummary.requestedPermissions,
            requestedHosts: enabledSummary.requestedHosts,
            unsupportedAPIs: enabledSummary.unsupportedAPIs,
            errors: enabledSummary.errors,
            diagnostics: enabledSummary.diagnostics,
            isEnabled: false,
            isLoaded: enabledSummary.isLoaded,
            permissionSnapshot: enabledSummary.permissionSnapshot,
            compatibilitySource: enabledSummary.compatibilitySource,
            compatibilityAssessment: enabledSummary.compatibilityAssessment,
            sourceDisplayName: enabledSummary.sourceDisplayName,
            iconPayload: enabledSummary.iconPayload,
            hasOptionsPage: enabledSummary.hasOptionsPage,
            hasCommands: enabledSummary.hasCommands,
            isPinned: enabledSummary.isPinned
        )
        pool.persistenceController.updateSummary(
            disabledSummary,
            in: space.id
        )
        XCTAssertTrue(
            provider.items(
                for: tab.id,
                in: space.id,
                context: BrowserExtensionWebpageMenuContext(
                    pageURL: pageURL,
                    documentURL: pageURL,
                    linkURL: nil,
                    sourceURL: nil,
                    selectionText: nil,
                    isEditable: false,
                    isMainFrame: true
                )
            ).isEmpty
        )
    }

    func testLoadingUnpackedContextMenuFixturePreparesCompatibilityBeforeFirstLoad()
        async throws
    {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appending(
            path: "crest-unpacked-context-menu-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: rootURL) }
        let space = BrowserSession.preview.spaces[0]
        let registry = BrowserExtensionWebpageMenuRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: rootURL
            ),
            registry: BrowserExtensionRegistry(),
            storedResourcePreparer:
                BrowserStoreWebExtensionStoredResourcePreparer(
                    fileManager: fileManager
                ),
            webpageMenuRegistry: registry
        )
        pool.setNativeMessagingHandler(
            BrowserNativeMessagingService(
                capability: .available,
                resolver: BrowserNativeMessagingHostManifestResolver(
                    searchDirectories: []
                ),
                webpageMenuRegistry: registry
            )
        )

        let installed = try await pool.loadUnpackedExtension(
            from: contextMenusFixtureURL,
            in: space
        )
        let clientID = BrowserExtensionServiceClientID.scoped(
            extensionID: installed.id,
            spaceID: space.id
        )
        var definitions: [BrowserExtensionWebpageMenuDefinition] = []
        for _ in 0..<200 {
            definitions = registry.definitions(for: clientID)
            if definitions.count == 14 { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(definitions.count, 14)
        XCTAssertEqual(
            pool.runtimeContextController.internallyGrantedPermissions(
                extensionID: installed.id,
                in: space.id
            ),
            ["nativeMessaging"]
        )
        XCTAssertEqual(
            pool.persistenceController.installation(
                extensionID: installed.id,
                in: space.id
            )?.source,
            .unpackedPackage
        )
        XCTAssertNotNil(
            installed.permissionSnapshot.grantedPermissions["contextMenus"]
        )
        XCTAssertNil(installed.permissionSnapshot.grantedPermissions["tabs"])
    }

    func testActionContextMenuOffersCommandsSettingsAndPinning() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-extension-menu-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root
            ),
            registry: BrowserExtensionRegistry()
        )
        pool.connect(browser: browser, pageProvider: PageProviderStub())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let installed = try await pool.loadUnpackedExtension(
            from: fixtureURL,
            in: space
        )
        pool.reconcileExtensionState(in: browser.session)
        let action = try XCTUnwrap(
            pool.toolbarActions(
                in: space.id,
                tabID: browser.session.selectedTab?.id
            )
            .first { $0.id == installed.id }
        )

        let menu = BrowserExtensionContextMenu().makeMenu(
            for: action,
            pool: pool,
            spaceID: space.id,
            manageExtensions: {}
        )
        let titles = menu.items.map(\.title)

        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertTrue(titles.contains("Add this site"))
        XCTAssertTrue(titles.contains("Extension Settings…"))
        XCTAssertTrue(titles.contains("Pin to Sidebar"))
        XCTAssertTrue(titles.contains("Manage Extensions…"))
    }

    func testActionContextMenuPinItemPinsTheExtension() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-extension-menu-pin-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let browser = BrowserStore.preview()
        let registry = BrowserExtensionRegistry()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root
            ),
            registry: registry
        )
        pool.connect(browser: browser, pageProvider: PageProviderStub())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let installed = try await pool.loadUnpackedExtension(
            from: fixtureURL,
            in: space
        )
        pool.reconcileExtensionState(in: browser.session)
        let action = try XCTUnwrap(
            pool.toolbarActions(
                in: space.id,
                tabID: browser.session.selectedTab?.id
            )
            .first { $0.id == installed.id }
        )
        let builder = BrowserExtensionContextMenu()
        let menu = builder.makeMenu(
            for: action,
            pool: pool,
            spaceID: space.id
        )
        let pinItem = try XCTUnwrap(
            menu.items.first { $0.title == "Pin to Sidebar" }
        )

        _ = pinItem.target?.perform(
            try XCTUnwrap(pinItem.action),
            with: pinItem
        )

        XCTAssertEqual(
            registry.installation(extensionID: installed.id, in: space.id)?
                .isPinned,
            true
        )
        XCTAssertFalse(
            menu.items.contains { $0.title == "Manage Extensions…" }
        )
    }

    // MARK: - Permission restore

    func testUnparsableStoredHostPatternIsReportedOnTheExtension()
        async throws
    {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderStub())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        var snapshot = BrowserExtensionPermissionSnapshot.empty
        snapshot.grantedHosts["not a match pattern"] = .distantFuture

        _ = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space,
            source: nil,
            permissionSnapshot: snapshot
        )

        let summary = try XCTUnwrap(
            pool.extensions(in: space.id).first { $0.id == extensionID }
        )
        XCTAssertTrue(
            summary.errors.contains {
                $0.contains("not a match pattern")
            },
            "A dropped website-access pattern was not reported: \(summary.errors)"
        )
        XCTAssertTrue(summary.needsAttention)
    }

    // MARK: - Support

    private func keyEvent(
        character: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 0
        )
    }

    private func makeTemporaryExtension(
        named name: String,
        extraManifest: [String: Any]
    ) throws -> URL {
        let fileManager = FileManager.default
        let url = fileManager.temporaryDirectory.appending(
            path: "crest-conformance-extension-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
        ]
        for (key, value) in extraManifest {
            manifest[key] = value
        }
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: url.appending(path: "manifest.json")
        )
        return url
    }

    private func makeContextMenuExtension() throws -> URL {
        let url = try makeTemporaryExtension(
            named: "Context Menu Probe",
            extraManifest: [
                "permissions": ["contextMenus"],
                "host_permissions": ["https://context-menu.crest.test/*"],
                "background": ["service_worker": "background.js"],
            ]
        )
        try Data(
            """
            chrome.contextMenus.removeAll(() => {
              chrome.contextMenus.create({
                id: "probe-tab",
                title: "Probe Tab",
                contexts: ["tab"]
              });
              chrome.contextMenus.create({
                id: "probe-image",
                title: "Probe Image",
                contexts: ["image"]
              });
              chrome.contextMenus.create({
                id: "probe-page",
                title: "Probe Page",
                contexts: ["page"]
              });
            });
            """.utf8
        ).write(to: url.appending(path: "background.js"))
        return url
    }

    private var extensionID: String {
        "com.pauldavis.crest.space-probe"
    }

    private var contextMenusFixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(
                path: "Fixtures/ContextMenusProbeExtension",
                directoryHint: .isDirectory
            )
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(
                path: "Fixtures/SpaceProbeExtension",
                directoryHint: .isDirectory
            )
    }
}
