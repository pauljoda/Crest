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

    private var extensionID: String {
        "com.pauldavis.crest.space-probe"
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
