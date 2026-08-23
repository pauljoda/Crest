import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionControllerPoolTests: XCTestCase {
    private final class PageProviderSpy: BrowserExtensionPageProviding {
        private(set) var preparedSessions: [BrowserSession] = []
        private(set) var selectedSessions: [BrowserSession] = []
        private(set) var readerModeRequests: [(TabID, Bool)] = []
        var webViews: [TabID: WKWebView] = [:]
        var readerModeStates: [TabID: BrowserReaderModeState] = [:]
        var windowGeometry = BrowserExtensionWindowGeometry.unavailable

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

        func prepareExtensionSelection(session: BrowserSession) {
            preparedSessions.append(session)
        }

        func select(session: BrowserSession) {
            selectedSessions.append(session)
        }
    }

    func testOneSpaceReusesOneEphemeralControllerByDefault() {
        let space = BrowserSession.preview.spaces[0]
        let pool = BrowserExtensionControllerPool()

        let first = pool.controller(for: space)
        let second = pool.controller(for: space)

        XCTAssertTrue(first === second)
        XCTAssertNil(first.configuration.identifier)
        XCTAssertFalse(first.configuration.isPersistent)
        XCTAssertFalse(
            first.configuration.defaultWebsiteDataStore.isPersistent
        )
        XCTAssertNil(first.configuration.defaultWebsiteDataStore.identifier)
    }

    func testExtensionWindowFocusTracksHostActivationAndSelectedSpace()
        throws
    {
        let browser = BrowserStore.preview()
        let selectedSpace = try XCTUnwrap(browser.session.selectedSpace)
        let otherSpace = try XCTUnwrap(
            browser.session.spaces.first(where: { $0.id != selectedSpace.id })
        )
        var reportedControllerIDs: [ObjectIdentifier] = []
        var reportedSpaceIDs: [SpaceID?] = []
        let coordinator = BrowserExtensionTabWindowCoordinator {
            controller,
            window in
            reportedControllerIDs.append(ObjectIdentifier(controller))
            reportedSpaceIDs.append(window?.spaceID)
        }
        coordinator.connect(
            browser: browser,
            pageProvider: PageProviderSpy(),
            openCommandSettings: { _, _ in false }
        )
        let selectedController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        let otherController = WKWebExtensionController(
            configuration: .nonPersistent()
        )

        // Connecting establishes the selected Space before its controller is
        // loaded. Registering that controller must publish the initial focus.
        coordinator.register(
            controller: otherController,
            spaceID: otherSpace.id
        )
        coordinator.register(
            controller: selectedController,
            spaceID: selectedSpace.id
        )

        XCTAssertEqual(reportedSpaceIDs, [selectedSpace.id])
        XCTAssertEqual(
            reportedControllerIDs,
            [ObjectIdentifier(selectedController)]
        )

        coordinator.setHostWindowFocused(false)
        coordinator.setHostWindowFocused(false)
        browser.selectSpace(otherSpace.id)
        coordinator.reconcile(session: browser.session)

        // Space selection while the host is inactive must not focus a WebKit
        // extension window, and duplicate inactive reports are ignored.
        XCTAssertEqual(reportedSpaceIDs, [selectedSpace.id, nil])
        XCTAssertEqual(
            reportedControllerIDs,
            [
                ObjectIdentifier(selectedController),
                ObjectIdentifier(selectedController),
            ]
        )

        coordinator.setHostWindowFocused(true)
        browser.selectSpace(selectedSpace.id)
        coordinator.reconcile(session: browser.session)

        XCTAssertEqual(
            reportedSpaceIDs,
            [selectedSpace.id, nil, otherSpace.id, nil, selectedSpace.id]
        )
        XCTAssertEqual(
            reportedControllerIDs,
            [
                ObjectIdentifier(selectedController),
                ObjectIdentifier(selectedController),
                ObjectIdentifier(otherController),
                ObjectIdentifier(otherController),
                ObjectIdentifier(selectedController),
            ]
        )

        coordinator.unregister(spaceID: selectedSpace.id)

        XCTAssertEqual(
            reportedSpaceIDs,
            [selectedSpace.id, nil, otherSpace.id, nil, selectedSpace.id, nil]
        )
        XCTAssertEqual(
            reportedControllerIDs.last,
            ObjectIdentifier(selectedController)
        )
    }

    func testEphemeralExtensionContextCanAccessOnlyItsIsolatedData()
        async throws
    {
        let pool = BrowserExtensionControllerPool()
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: BrowserSession.preview.spaces[0]
        )

        // An ephemeral pool drives web views on a non-persistent data store,
        // which WebKit classifies as private data. Without this grant WebKit
        // refuses the extension content scripts, messaging, and tab access, so
        // every isolated launch would silently run its extensions dead. Private
        // browsing is fenced off by having no extension controller at all.
        XCTAssertTrue(context.hasAccessToPrivateData)
        XCTAssertFalse(
            pool.controller(for: BrowserSession.preview.spaces[0])
                .configuration.isPersistent)
    }

    /// Reading `popupPopover` preloads the popup document, so Crest asks WebKit
    /// to load the extension background before performing the action. The
    /// action itself must still go through `WKWebExtensionContext` so WebKit
    /// owns its user-gesture and popup-delegate lifecycle.
    func testToolbarPopupIsPresentedAfterItsBackgroundContentIsAskedFor()
        async throws
    {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-popup-ordering-extension-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: extensionURL) }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Popup Ordering Test",
            "version": "1.0",
            "background": ["service_worker": "background.js"],
            "action": ["default_popup": "popup.html"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        try Data(
            """
            chrome.runtime.onMessage.addListener((message, sender, reply) => {
                reply({ready: true});
                return true;
            });
            """.utf8
        ).write(to: extensionURL.appending(path: "background.js"))
        try Data(
            """
            <!doctype html><title>Ready</title>
            <body>Loading</body><script src="popup.js"></script>
            """.utf8
        ).write(to: extensionURL.appending(path: "popup.html"))
        try Data(
            """
            chrome.runtime.sendMessage({check: true}, (response) => {
                document.body.textContent = response?.ready ? "Ready" : "Failed";
            });
            """.utf8
        ).write(to: extensionURL.appending(path: "popup.js"))

        let pool = BrowserExtensionControllerPool()
        let space = BrowserSession.preview.spaces[0]
        _ = try await pool.loadUnpackedExtension(from: extensionURL, in: space)
        let action = try XCTUnwrap(
            pool.toolbarActions(in: space.id, tabID: nil).first
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let sourceView = NSView(
            frame: CGRect(x: 20, y: 540, width: 24, height: 24)
        )
        window.contentView?.addSubview(sourceView)
        window.orderFront(nil)
        defer {
            action.action.closePopup()
            window.close()
        }

        // The product gives a cold background three seconds before it presents
        // nothing at all, a deadline that answers to how long a click stays
        // remembered rather than to how busy the machine is. What this test
        // claims is the order of the two steps, so it hands the warm-up room a
        // loaded machine can still meet: a deadline that expires here presents no
        // popup, and no amount of waiting afterwards would find one.
        pool.tabWindowCoordinator.popupBackgroundWarmUpDeadline = .seconds(8)
        // AppKit announces the presentation itself, so wait for that rather than
        // sleeping out the warm-up and then polling `popupPopover`: every access
        // to that property preloads the popup document this ordering exists to
        // hold back until the background can answer it.
        let presented = expectation(
            forNotification: NSPopover.didShowNotification,
            object: nil
        )

        pool.perform(
            action,
            popupAnchor: BrowserExtensionPopupAnchor(sourceView: sourceView)
        )

        await fulfillment(of: [presented], timeout: 10)
        XCTAssertEqual(
            action.action.popupPopover?.isShown,
            true,
            "The popup was never presented after its background loaded."
        )
        let popupWebView = try XCTUnwrap(action.action.popupWebView)
        var popupText: String?
        for _ in 0..<400 {
            popupText =
                try await popupWebView.evaluateJavaScript(
                    "document.body.innerText"
                ) as? String
            if popupText == "Ready" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(
            popupText,
            "Ready",
            "The presented popup never had its opening message answered."
        )
    }

    func testPerformingToolbarPopupPresentsItsReadyExtensionDocument()
        async throws
    {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-popup-preload-extension-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: extensionURL) }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Popup Preload Test",
            "version": "1.0",
            "background": ["service_worker": "background.js"],
            "action": ["default_popup": "popup.html"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        try Data(
            """
            chrome.runtime.onMessage.addListener((message, sender, reply) => {
                reply({ready: true});
                return true;
            });
            """.utf8
        ).write(
            to: extensionURL.appending(path: "background.js")
        )
        try Data(
            """
            <!doctype html><title>Ready</title>
            <body>Loading</body><script src="popup.js"></script>
            """.utf8
        ).write(
            to: extensionURL.appending(path: "popup.html")
        )
        try Data(
            """
            chrome.runtime.sendMessage({check: true}, (response) => {
                document.body.textContent = response?.ready ? "Ready" : "Failed";
            });
            """.utf8
        ).write(to: extensionURL.appending(path: "popup.js"))
        let pool = BrowserExtensionControllerPool()
        let space = BrowserSession.preview.spaces[0]
        _ = try await pool.loadUnpackedExtension(
            from: extensionURL,
            in: space
        )
        let action = try XCTUnwrap(
            pool.toolbarActions(in: space.id, tabID: nil).first
        )

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let sourceView = NSView(frame: CGRect(x: 20, y: 540, width: 24, height: 24))
        window.contentView?.addSubview(sourceView)
        window.orderFront(nil)

        pool.perform(
            action,
            popupAnchor: BrowserExtensionPopupAnchor(sourceView: sourceView)
        )

        // `popupPopover` preloads the popup, so let the background warm-up
        // finish before observing WebKit's presentation state.
        try await Task.sleep(
            for: BrowserExtensionPopupBackgroundWarmUp.defaultDeadline
                + .milliseconds(100)
        )
        for _ in 0..<200 where action.action.popupPopover?.isShown != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        let popupWebView = try XCTUnwrap(action.action.popupWebView)
        var popupText: String?
        for _ in 0..<200 {
            popupText =
                try await popupWebView.evaluateJavaScript(
                    "document.body.innerText"
                ) as? String
            if popupText == "Ready" { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(action.action.popupPopover?.isShown == true)
        XCTAssertEqual(popupText, "Ready")

        pool.perform(
            action,
            popupAnchor: BrowserExtensionPopupAnchor(sourceView: sourceView)
        )
        for _ in 0..<200 where action.action.popupPopover?.isShown == true {
            try await Task.sleep(for: .milliseconds(10))
        }
        pool.perform(
            action,
            popupAnchor: BrowserExtensionPopupAnchor(sourceView: sourceView)
        )
        try await Task.sleep(
            for: BrowserExtensionPopupBackgroundWarmUp.defaultDeadline
                + .milliseconds(100)
        )
        for _ in 0..<200 where action.action.popupPopover?.isShown != true {
            try await Task.sleep(for: .milliseconds(10))
        }

        let reopenedPopupWebView = try XCTUnwrap(
            action.action.popupWebView
        )
        var reopenedPopupText: String?
        for _ in 0..<200 {
            reopenedPopupText =
                try await reopenedPopupWebView.evaluateJavaScript(
                    "document.body.innerText"
                ) as? String
            if reopenedPopupText == "Ready" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(action.action.popupPopover?.isShown == true)
        XCTAssertEqual(
            reopenedPopupText,
            "Ready"
        )
        pool.perform(
            action,
            popupAnchor: BrowserExtensionPopupAnchor(sourceView: sourceView)
        )
        for _ in 0..<200 where action.action.popupPopover?.isShown == true {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(250))
        window.close()
    }

    func testLoadedExtensionContextIsInspectableUnderItsDisplayName()
        async throws
    {
        let pool = BrowserExtensionControllerPool()
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: BrowserSession.preview.spaces[0]
        )

        XCTAssertTrue(context.isInspectable)
        XCTAssertEqual(
            context.inspectionName,
            context.webExtension.displayName
        )
    }

    func testStandaloneNativeMessagingExtensionIsRejectedBeforeLoad()
        async throws
    {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-native-messaging-extension-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: extensionURL) }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Native Companion Test",
            "version": "1.0",
            "permissions": ["nativeMessaging"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        let pool = BrowserExtensionControllerPool()
        let space = BrowserSession.preview.spaces[0]

        do {
            _ = try await pool.loadExtension(
                at: extensionURL,
                extensionID: "com.example.native-companion",
                in: space
            )
            XCTFail("A standalone native-messaging extension was loaded.")
        } catch let error as BrowserExtensionCompatibilityError {
            XCTAssertEqual(
                error.assessment.blockingIssues.map(\.kind),
                [.unverifiedNativeMessaging]
            )
        }

        XCTAssertNil(
            pool.loadedContext(
                extensionID: "com.example.native-companion",
                in: space.id
            )
        )
    }

    func testVerifiedChromeExtensionReachesNativeMessagingDelegate()
        async throws
    {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-native-delegate-extension-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: extensionURL) }
        let permissions = [
            "alarms",
            "contextMenus",
            "downloads",
            "idle",
            "management",
            "nativeMessaging",
            "notifications",
            "offscreen",
            "privacy",
            "scripting",
            "storage",
            "tabs",
            "webNavigation",
            "webRequest",
            "webRequestAuthProvider",
            "declarativeNetRequestWithHostAccess",
        ]
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Native Delegate Test",
            "version": "1.0",
            "permissions": permissions,
            "background": [
                "service_worker": "background.js",
                "type": "module",
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        try Data(
            """
            const immediateChromeCreatedNavigationTarget =
                typeof chrome.webNavigation
                    ?.onCreatedNavigationTarget?.addListener;
            const stored = await browser.storage.local.get();
            const emptyMessage = browser.i18n.getMessage('');
            const menuID = browser.contextMenus.create({
                id: 'subscribe',
                title: 'Subscribe',
                contexts: ['link'],
                targetUrlPatterns: [
                    'abp:*',
                    'https://subscribe.example/*'
                ]
            });
            await new Promise((resolve) => setTimeout(resolve, 250));
            await browser.runtime.sendNativeMessage(
                'com.example.echo',
                {
                    ping: 'pong',
                    storedKeys: Object.keys(stored).length,
                    emptyMessage,
                    menuID,
                    browserCreatedNavigationTarget:
                        typeof browser.webNavigation
                            .onCreatedNavigationTarget?.addListener,
                    chromeCreatedNavigationTarget:
                        typeof chrome.webNavigation
                            .onCreatedNavigationTarget?.addListener,
                    immediateChromeCreatedNavigationTarget,
                    manifestVersion:
                        browser.runtime.getManifest().manifest_version,
                    capabilities: {
                        managedStorage:
                            typeof browser.storage.managed?.get,
                        sessionStorage:
                            typeof browser.storage.session?.get,
                        managementSelf:
                            typeof browser.management?.getSelf,
                        notificationCreate:
                            typeof chrome.notifications?.create,
                        notificationClick:
                            typeof chrome.notifications?.onClicked
                                ?.addListener,
                        offscreenCreate:
                            typeof chrome.offscreen?.createDocument,
                        passwordSavingPreference:
                            typeof chrome.privacy?.services
                                ?.passwordSavingEnabled?.get,
                        hostAccessRequest:
                            typeof chrome.permissions
                                ?.addHostAccessRequest,
                        requestIdleCallback:
                            typeof globalThis.requestIdleCallback,
                        serviceWorkerClients:
                            typeof globalThis.clients?.matchAll,
                        requestCacheFlush:
                            typeof chrome.webRequest
                                ?.handlerBehaviorChanged,
                        authRequestEvent:
                            typeof browser.webRequest?.onAuthRequired
                                ?.addListener,
                        idleState:
                            typeof browser.idle?.queryState,
                        actionSettings:
                            typeof chrome.action?.getUserSettings,
                        shadowRootAccess:
                            typeof chrome.dom?.openOrClosedShadowRoot,
                        navigationAllFrames:
                            typeof browser.webNavigation?.getAllFrames,
                        navigationFrame:
                            typeof browser.webNavigation?.getFrame,
                        updateAvailableEvent:
                            typeof browser.runtime.onUpdateAvailable
                                ?.addListener
                    }
                }
            );
            """.utf8
        ).write(to: extensionURL.appending(path: "background.js"))
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            ))
        let handler = NativeMessagingHandlerSpy()
        let pool = BrowserExtensionControllerPool()
        pool.setNativeMessagingHandler(handler)
        let source = BrowserExtensionInstallationSource.chromeWebStore(
            BrowserChromeWebStoreSource(
                extensionID: extensionID,
                storeURL: try XCTUnwrap(
                    URL(
                        string: "https://chromewebstore.google.com/detail/test/\(extensionID.rawValue)"
                    )),
                crxSHA256Hex: String(repeating: "a", count: 64),
                publisherKeyHashHex: String(repeating: "b", count: 64)
            )
        )
        XCTAssertTrue(
            try BrowserWebExtensionCompatibilityPackagePreparer()
                .installCompatibilityLayer(
                    in: extensionURL,
                    requestedPermissions: permissions,
                    runtimeIdentity: BrowserExtensionRuntimeIdentity(
                        extensionID: extensionID.rawValue,
                        uniqueIdentifier: "native-delegate-test",
                        baseURL: try XCTUnwrap(
                            URL(
                                string:
                                    "crest-extension://native-delegate-test/"
                            )
                        )
                    )
                )
        )

        let loadedContext = try await pool.loadExtension(
            at: extensionURL,
            extensionID: extensionID.rawValue,
            in: BrowserSession.preview.spaces[0],
            source: source,
            permissionSnapshot:
                BrowserExtensionInstallationPermissionPolicy
                .reviewedRequiredAccess(
                    permissions: permissions,
                    hosts: []
                )
        )
        await fulfillment(of: [handler.receivedMessage], timeout: 5)

        XCTAssertEqual(handler.hostName, "com.example.echo")
        XCTAssertEqual(handler.extensionID, extensionID)
        XCTAssertEqual(
            handler.authorization?.grantedPermissions,
            Set(permissions)
        )
        XCTAssertEqual(
            handler.authorization?.clientID?.rawValue,
            loadedContext.uniqueIdentifier
        )
        XCTAssertEqual(
            (handler.message as? [String: Any])?["ping"] as? String,
            "pong"
        )
        XCTAssertEqual(
            (handler.message as? [String: Any])?["storedKeys"] as? Int,
            0
        )
        XCTAssertEqual(
            (handler.message as? [String: Any])?["emptyMessage"] as? String,
            ""
        )
        XCTAssertEqual(
            (handler.message as? [String: Any])?["menuID"] as? String,
            "subscribe"
        )
        XCTAssertEqual(
            (handler.message as? [String: Any])?[
                "browserCreatedNavigationTarget"
            ] as? String,
            "function"
        )
        XCTAssertEqual(
            (handler.message as? [String: Any])?[
                "chromeCreatedNavigationTarget"
            ] as? String,
            "function"
        )
        XCTAssertEqual(
            (handler.message as? [String: Any])?[
                "immediateChromeCreatedNavigationTarget"
            ] as? String,
            "function"
        )
        XCTAssertEqual(
            (handler.message as? [String: Any])?["manifestVersion"] as? Int,
            3
        )
        let capabilities = try XCTUnwrap(
            (handler.message as? [String: Any])?["capabilities"]
                as? [String: String]
        )
        for (name, kind) in capabilities {
            XCTAssertEqual(kind, "function", "Missing capability: \(name)")
        }
        let compatibilityErrors = loadedContext.errors.map(
            \.localizedDescription
        ).filter {
            $0.contains("i18n.getMessage")
                || $0.contains("targetUrlPatterns")
                || $0.contains("onUpdateAvailable")
        }
        XCTAssertTrue(
            compatibilityErrors.isEmpty,
            "Compatibility errors: \(compatibilityErrors)"
        )
    }

    func testMappedIdleEventTraversesTheVerifiedCapabilityBroker()
        async throws
    {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-idle-capability-extension-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: extensionURL) }
        let permissions = ["idle", "nativeMessaging"]
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Idle Capability Test",
            "version": "1.0",
            "permissions": permissions,
            "background": ["service_worker": "background.js"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        try Data(
            """
            browser.idle.onStateChanged.addListener(async (state) => {
                await browser.runtime.sendNativeMessage(
                    "com.example.idle_capture",
                    { state }
                );
            });
            browser.idle.setDetectionInterval(45);
            """.utf8
        ).write(to: extensionURL.appending(path: "background.js"))
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        XCTAssertTrue(
            try BrowserWebExtensionCompatibilityPackagePreparer()
                .installCompatibilityLayer(
                    in: extensionURL,
                    requestedPermissions: permissions,
                    runtimeIdentity: BrowserExtensionRuntimeIdentity(
                        extensionID: extensionID.rawValue,
                        uniqueIdentifier: "idle-capability-test",
                        baseURL: try XCTUnwrap(
                            URL(
                                string:
                                    "crest-extension://idle-capability-test/"
                            )
                        )
                    )
                )
        )
        let handler = IdleCapabilityBrokerHandler()
        let pool = BrowserExtensionControllerPool()
        pool.setNativeMessagingHandler(handler)
        let source = BrowserExtensionInstallationSource.chromeWebStore(
            BrowserChromeWebStoreSource(
                extensionID: extensionID,
                storeURL: try XCTUnwrap(
                    URL(
                        string: "https://chromewebstore.google.com/detail/test/\(extensionID.rawValue)"
                    )
                ),
                crxSHA256Hex: String(repeating: "a", count: 64),
                publisherKeyHashHex: String(repeating: "b", count: 64)
            )
        )

        _ = try await pool.loadExtension(
            at: extensionURL,
            extensionID: extensionID.rawValue,
            in: BrowserSession.preview.spaces[0],
            source: source,
            permissionSnapshot:
                BrowserExtensionInstallationPermissionPolicy
                .reviewedRequiredAccess(
                    permissions: permissions,
                    hosts: []
                )
        )
        await fulfillment(of: [handler.receivedState], timeout: 5)

        XCTAssertEqual(handler.hostName, "com.example.idle_capture")
        XCTAssertEqual(handler.state, "idle")
        XCTAssertEqual(
            handler.authorization?.grantedPermissions,
            Set(permissions)
        )
    }

    func testMappedNotificationEventTraversesTheVerifiedCapabilityBroker()
        async throws
    {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-notification-capability-extension-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: extensionURL) }
        let permissions = ["nativeMessaging", "notifications"]
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Notification Capability Test",
            "version": "1.0",
            "permissions": permissions,
            "background": ["service_worker": "background.js"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        try Data(
            """
            browser.notifications.onClicked.addListener(async (identifier) => {
                await browser.runtime.sendNativeMessage(
                    "com.example.notification_capture",
                    { identifier }
                );
            });
            browser.notifications.create("saved", {
                type: "basic",
                title: "Saved",
                message: "The login was saved."
            });
            """.utf8
        ).write(to: extensionURL.appending(path: "background.js"))
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        XCTAssertTrue(
            try BrowserWebExtensionCompatibilityPackagePreparer()
                .installCompatibilityLayer(
                    in: extensionURL,
                    requestedPermissions: permissions,
                    runtimeIdentity: BrowserExtensionRuntimeIdentity(
                        extensionID: extensionID.rawValue,
                        uniqueIdentifier: "notification-capability-test",
                        baseURL: try XCTUnwrap(
                            URL(
                                string:
                                    "crest-extension://notification-capability-test/"
                            )
                        )
                    )
                )
        )
        let handler = NotificationCapabilityBrokerHandler()
        let pool = BrowserExtensionControllerPool()
        pool.setNativeMessagingHandler(handler)
        let source = BrowserExtensionInstallationSource.chromeWebStore(
            BrowserChromeWebStoreSource(
                extensionID: extensionID,
                storeURL: try XCTUnwrap(
                    URL(
                        string: "https://chromewebstore.google.com/detail/test/\(extensionID.rawValue)"
                    )
                ),
                crxSHA256Hex: String(repeating: "a", count: 64),
                publisherKeyHashHex: String(repeating: "b", count: 64)
            )
        )

        let loadedContext = try await pool.loadExtension(
            at: extensionURL,
            extensionID: extensionID.rawValue,
            in: BrowserSession.preview.spaces[0],
            source: source,
            permissionSnapshot:
                BrowserExtensionInstallationPermissionPolicy
                .reviewedRequiredAccess(
                    permissions: permissions,
                    hosts: []
                )
        )
        await fulfillment(of: [handler.createdNotification], timeout: 5)
        try handler.simulateClick()
        await fulfillment(of: [handler.receivedClick], timeout: 5)

        XCTAssertEqual(handler.clickedIdentifier, "saved")
        XCTAssertEqual(
            handler.authorization?.grantedPermissions,
            Set(permissions)
        )
        XCTAssertEqual(
            handler.authorization?.clientID?.rawValue,
            loadedContext.uniqueIdentifier
        )
    }

    func testVerifiedFirefoxExtensionReachesNativeMessagingDelegate()
        async throws
    {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-firefox-native-delegate-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: extensionURL) }
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Firefox Native Delegate Test",
            "version": "1.0",
            "permissions": ["nativeMessaging"],
            "background": ["scripts": ["background.js"]],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        try Data(
            "browser.runtime.sendNativeMessage('com.example.echo', {ping: 'pong'});"
                .utf8
        ).write(to: extensionURL.appending(path: "background.js"))
        let extensionID = try XCTUnwrap(
            BrowserMozillaExtensionID("native-delegate@crest.test")
        )
        let handler = NativeMessagingHandlerSpy()
        let pool = BrowserExtensionControllerPool()
        pool.setNativeMessagingHandler(handler)
        let source = BrowserExtensionInstallationSource.mozillaAddons(
            BrowserMozillaAddonsSource(
                slug: try XCTUnwrap(
                    BrowserMozillaAddonSlug("native-delegate")
                ),
                extensionID: extensionID,
                storeURL: try XCTUnwrap(
                    URL(
                        string:
                            "https://addons.mozilla.org/firefox/addon/native-delegate/"
                    )
                ),
                version: "1.0",
                xpiSHA256Hex: String(repeating: "a", count: 64)
            )
        )

        _ = try await pool.loadExtension(
            at: extensionURL,
            extensionID: extensionID.rawValue,
            in: BrowserSession.preview.spaces[0],
            source: source,
            permissionSnapshot:
                BrowserExtensionInstallationPermissionPolicy
                .reviewedRequiredAccess(
                    permissions: ["nativeMessaging"],
                    hosts: []
                )
        )
        await fulfillment(of: [handler.receivedMessage], timeout: 5)

        XCTAssertEqual(handler.hostName, "com.example.echo")
        XCTAssertEqual(handler.extensionIdentity, .mozillaAddons(extensionID))
        XCTAssertEqual(
            (handler.message as? [String: String])?["ping"],
            "pong"
        )
    }

    func testPersistentNativeMessagingPortSurvivesDelayedCompanionReply()
        async throws
    {
        guard
            BrowserPlatformExtensionNativeMessagingCapability.currentBuild
                == .available
        else {
            throw XCTSkip(
                "This build cannot launch native hosts."
            )
        }
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appending(
            path: "crest-native-port-retention-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let extensionURL = rootURL.appending(
            path: "Extension",
            directoryHint: .isDirectory
        )
        let hostDirectoryURL = rootURL.appending(
            path: "NativeMessagingHosts",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: hostDirectoryURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: rootURL) }

        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            ))
        let hostName = "com.example.delayed_echo"
        let executableURL = rootURL.appending(path: "delayed-echo.py")
        let hostScript = """
            #!/usr/bin/python3
            import json, struct, sys, time
            header = sys.stdin.buffer.read(4)
            size = struct.unpack('<I', header)[0]
            message = json.loads(sys.stdin.buffer.read(size))
            time.sleep(0.25)
            payload = json.dumps({'echo': message}).encode('utf-8')
            sys.stdout.buffer.write(struct.pack('<I', len(payload)) + payload)
            sys.stdout.buffer.flush()
            time.sleep(0.25)
            """
        try Data(hostScript.utf8).write(to: executableURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        let nativeManifest: [String: Any] = [
            "name": hostName,
            "path": executableURL.path,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://\(extensionID.rawValue)/"
            ],
        ]
        try JSONSerialization.data(withJSONObject: nativeManifest).write(
            to: hostDirectoryURL.appending(path: "\(hostName).json")
        )
        let extensionManifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Persistent Native Port Test",
            "version": "1.0",
            "permissions": ["nativeMessaging", "storage"],
            "background": ["service_worker": "background.js"],
        ]
        try JSONSerialization.data(withJSONObject: extensionManifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        let backgroundScript = """
            globalThis.nativePort = browser.runtime.connectNative('\(hostName)');
            globalThis.nativePort.onMessage.addListener(async message => {
              await browser.storage.local.set({ nativeEcho: message.echo?.ping });
            });
            globalThis.nativePort.postMessage({ ping: 'pong' });
            """
        try Data(backgroundScript.utf8).write(
            to: extensionURL.appending(path: "background.js")
        )

        let service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: [hostDirectoryURL]
            )
        )
        let pool = BrowserExtensionControllerPool()
        pool.setNativeMessagingHandler(service)
        let space = BrowserSession.preview.spaces[0]
        let source = BrowserExtensionInstallationSource.chromeWebStore(
            BrowserChromeWebStoreSource(
                extensionID: extensionID,
                storeURL: try XCTUnwrap(
                    URL(
                        string: "https://chromewebstore.google.com/detail/test/\(extensionID.rawValue)"
                    )),
                crxSHA256Hex: String(repeating: "a", count: 64),
                publisherKeyHashHex: String(repeating: "b", count: 64)
            )
        )
        let context = try await pool.loadExtension(
            at: extensionURL,
            extensionID: extensionID.rawValue,
            in: space,
            source: source,
            permissionSnapshot:
                BrowserExtensionInstallationPermissionPolicy
                .reviewedRequiredAccess(
                    permissions: ["nativeMessaging", "storage"],
                    hosts: []
                )
        )
        XCTAssertTrue(context.hasAccessToPrivateData)
        let configuration = try XCTUnwrap(context.webViewConfiguration)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let extensionPageURL = context.baseURL.appending(path: "manifest.json")
        let waiter = ExtensionNavigationWaiter(webView: webView)
        try await waiter.load(
            simulatedRequest: URLRequest(url: extensionPageURL),
            responseHTML: "<!doctype html><html><body>Native echo</body></html>"
        )

        var nativeEcho: String?
        for _ in 0..<200 {
            nativeEcho =
                try await webView.callAsyncJavaScript(
                    "return (await browser.storage.local.get('nativeEcho')).nativeEcho;",
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                ) as? String
            if nativeEcho != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(nativeEcho, "pong")
    }

    func testDifferentSpacesReceiveDifferentEphemeralControllersAndDataStores() {
        let work = BrowserSession.preview.spaces[0]
        let personal = BrowserSession.preview.spaces[1]
        let pool = BrowserExtensionControllerPool()

        let workController = pool.controller(for: work)
        let personalController = pool.controller(for: personal)

        XCTAssertFalse(workController === personalController)
        XCTAssertFalse(
            workController.configuration.defaultWebsiteDataStore
                === personalController.configuration.defaultWebsiteDataStore
        )
        XCTAssertFalse(
            workController.configuration.defaultWebsiteDataStore.isPersistent
        )
        XCTAssertFalse(
            personalController.configuration.defaultWebsiteDataStore.isPersistent
        )
    }

    func testTabAndWindowAdaptersExposeOnlyTheirOwningSpace() async throws {
        let browser = BrowserStore.preview()
        let pageProvider = PageProviderSpy()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: pageProvider)
        let work = browser.session.spaces[0]
        let personal = browser.session.spaces[1]
        let workContext = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: work
        )
        let personalContext = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: personal
        )

        pool.reconcileExtensionState(in: browser.session)
        let workWindow = try XCTUnwrap(pool.extensionWindow(in: work.id))
        let personalWindow = try XCTUnwrap(pool.extensionWindow(in: personal.id))
        let workTabs = workWindow.tabs(for: workContext)
        let personalTabs = personalWindow.tabs(for: personalContext)

        XCTAssertEqual(workTabs.count, work.tabs.count)
        XCTAssertEqual(personalTabs.count, personal.tabs.count)
        XCTAssertTrue(workWindow.tabs(for: personalContext).isEmpty)
        XCTAssertTrue(personalWindow.tabs(for: workContext).isEmpty)
        let expectedActive = try XCTUnwrap(
            pool.extensionTab(try XCTUnwrap(work.selectedTabID), in: work.id)
        )
        let active = try XCTUnwrap(
            workWindow.activeTab(for: workContext)
                as? BrowserExtensionTabAdapter
        )
        let first = try XCTUnwrap(workTabs.first as? BrowserExtensionTabAdapter)
        let repeatedFirst = try XCTUnwrap(
            workWindow.tabs(for: workContext).first
                as? BrowserExtensionTabAdapter
        )
        XCTAssertTrue(active === expectedActive)
        XCTAssertTrue(first === repeatedFirst)
    }

    func testTabAdapterRejectsAContextOwnedByAnotherSpace() async throws {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderSpy())
        let work = browser.session.spaces[0]
        let personal = browser.session.spaces[1]
        _ = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: work
        )
        let personalContext = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: personal
        )
        let tab = try XCTUnwrap(work.tabs.first)
        let adapter = try XCTUnwrap(pool.extensionTab(tab.id, in: work.id))
        let originalSession = browser.session
        var activationError: Error?

        adapter.activate(for: personalContext) { activationError = $0 }

        XCTAssertNotNil(activationError)
        XCTAssertEqual(browser.session, originalSession)
        XCTAssertNil(adapter.window(for: personalContext))
        XCTAssertEqual(adapter.indexInWindow(for: personalContext), NSNotFound)
        XCTAssertNil(adapter.webView(for: personalContext))
        XCTAssertNil(adapter.title(for: personalContext))
        XCTAssertNil(adapter.url(for: personalContext))
    }

    func testAdapterActivationAndPinningMutateOnlyTheOwningSpace() async throws {
        let browser = BrowserStore.preview()
        let pageProvider = PageProviderSpy()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: pageProvider)
        let personal = browser.session.spaces[1]
        let personalContext = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: personal
        )
        let currentTab = try XCTUnwrap(personal.currentTabs.first)
        let adapter = try XCTUnwrap(
            pool.extensionTab(currentTab.id, in: personal.id)
        )
        var activationError: Error?
        adapter.activate(for: personalContext) { activationError = $0 }

        XCTAssertNil(activationError)
        XCTAssertEqual(browser.session.selectedSpaceID, personal.id)
        XCTAssertEqual(browser.session.selectedTab?.id, currentTab.id)
        XCTAssertEqual(pageProvider.selectedSessions.last?.selectedTab?.id, currentTab.id)

        var pinningError: Error?
        adapter.setPinned(true, for: personalContext) { pinningError = $0 }

        XCTAssertNil(pinningError)
        XCTAssertEqual(
            browser.session.space(id: personal.id)?.tabs.first(where: {
                $0.id == currentTab.id
            })?.placement,
            .pinned
        )
        XCTAssertFalse(
            browser.session.spaces[0].tabs.contains(where: { $0.id == currentTab.id })
        )
    }

    func testExtensionCommandRouteOpensCrestSettingsWithoutLoadingTheTab()
        async throws
    {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderSpy())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        pool.reconcileExtensionState(in: browser.session)
        let tab = try XCTUnwrap(browser.session.selectedTab)
        let originalURL = tab.url
        let adapter = try XCTUnwrap(
            pool.extensionTab(tab.id, in: space.id)
        )
        let commandURL = try XCTUnwrap(
            URL(
                string: "chrome://extensions/configureCommands?command=eimadpbcbfnmbkopoojfekhnkhdbieeh-addSite"
            )
        )
        var routedCommand: BrowserExtensionCommandSettingsRoute?
        var routedSpaceID: SpaceID?
        pool.setCommandSettingsHandler { route, spaceID in
            routedCommand = route
            routedSpaceID = spaceID
        }
        var loadError: Error?

        adapter.loadURL(commandURL, for: context) { loadError = $0 }

        XCTAssertNil(loadError)
        XCTAssertEqual(routedCommand?.commandID, "addSite")
        XCTAssertEqual(routedSpaceID, space.id)
        XCTAssertEqual(browser.session.selectedTab?.id, tab.id)
        XCTAssertEqual(browser.session.selectedTab?.url, originalURL)
    }

    func testAdapterHidesSensitiveMetadataUntilTabsPermissionIsGranted() async throws {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderSpy())
        let work = browser.session.spaces[0]
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: work
        )
        let tab = try XCTUnwrap(work.tabs.first(where: { $0.url != nil }))
        let adapter = try XCTUnwrap(pool.extensionTab(tab.id, in: work.id))

        XCTAssertNil(adapter.url(for: context))
        XCTAssertNil(adapter.title(for: context))

        context.setPermissionStatus(.grantedExplicitly, for: .tabs)

        XCTAssertEqual(adapter.url(for: context), tab.url)
        XCTAssertEqual(adapter.title(for: context), tab.title)
    }

    func testAdapterRevealsSensitiveMetadataForAnActiveTabActionGesture()
        async throws
    {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderSpy())
        let work = browser.session.spaces[0]
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: work
        )
        let tab = try XCTUnwrap(work.tabs.first(where: { $0.url != nil }))
        let adapter = try XCTUnwrap(pool.extensionTab(tab.id, in: work.id))

        XCTAssertTrue(
            context.webExtension.requestedPermissions.contains(.activeTab)
        )
        XCTAssertNil(adapter.url(for: context))
        XCTAssertNil(adapter.title(for: context))

        context.userGesturePerformed(in: adapter)

        XCTAssertTrue(context.hasActiveUserGesture(in: adapter))
        XCTAssertEqual(adapter.url(for: context), tab.url)
        XCTAssertEqual(adapter.title(for: context), tab.title)
    }

    func testAdapterRevealsItsOwnExtensionPageWithoutTabsPermission() async throws {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        pool.connect(browser: browser, pageProvider: PageProviderSpy())
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        let optionsURL = try XCTUnwrap(context.optionsPageURL)

        pool.openOptionsPage(extensionID: extensionID, in: space.id)

        let tab = try XCTUnwrap(browser.session.selectedTab)
        let adapter = try XCTUnwrap(pool.extensionTab(tab.id, in: space.id))
        XCTAssertFalse(context.hasPermission(.tabs, in: adapter))
        XCTAssertEqual(adapter.url(for: context), optionsURL)
        XCTAssertEqual(adapter.title(for: context), tab.title)
    }

    func testPageConfigurationUsesTheOwningSpacesController() {
        let space = BrowserSession.preview.spaces[0]
        let controller = BrowserExtensionControllerPool().controller(for: space)

        let configuration = BrowserPageConfiguration.make(
            for: space.profile,
            webExtensionController: controller
        )

        XCTAssertTrue(configuration.webExtensionController === controller)
    }

    func testOpeningExtensionOptionsAttachesResourcesAndRuntimeBeforeNavigation() async throws {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        let pages = BrowserPagePool(
            monitorsMemoryPressure: false,
            extensionControllerPool: pool
        )
        pool.connect(browser: browser, pageProvider: pages)
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        let optionsURL = try XCTUnwrap(context.optionsPageURL)

        pool.openOptionsPage(extensionID: extensionID, in: space.id)

        XCTAssertEqual(browser.session.selectedSpaceID, space.id)
        XCTAssertEqual(browser.session.selectedTab?.url, optionsURL)
        XCTAssertEqual(pages.activeTabID, browser.session.selectedTab?.id)
        let page = try XCTUnwrap(pages.activePage)
        XCTAssertEqual(page.pendingNavigationURL, optionsURL)
        for _ in 0..<200 {
            let runtimeReady =
                try? await page.webView.evaluateJavaScript(
                    "document.documentElement.dataset.runtimeReady"
                ) as? String
            if runtimeReady == "true" {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        let runtimeReady =
            try await page.webView.evaluateJavaScript(
                "document.documentElement.dataset.runtimeReady"
            ) as? String
        let background =
            try await page.webView.evaluateJavaScript(
                "getComputedStyle(document.documentElement).backgroundColor"
            ) as? String

        XCTAssertNil(page.navigationFailure, String(describing: page.navigationFailure))
        XCTAssertEqual(runtimeReady, "true")
        XCTAssertEqual(background, "rgb(17, 34, 51)")
        XCTAssertEqual(optionsURL.path, "/options/index.html")
        XCTAssertEqual(page.webView.url?.path, optionsURL.path)
    }

    func testAdapterLoadSwapsBetweenStandardAndExtensionPageConfigurations()
        async throws
    {
        let browser = BrowserStore.preview()
        let pool = BrowserExtensionControllerPool()
        let pages = BrowserPagePool(
            monitorsMemoryPressure: false,
            extensionControllerPool: pool
        )
        pool.connect(browser: browser, pageProvider: pages)
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        pages.select(session: browser.session)
        let tab = try XCTUnwrap(browser.session.selectedTab)
        let standardPage = try XCTUnwrap(pages.activePage)
        let adapter = try XCTUnwrap(pool.extensionTab(tab.id, in: space.id))
        let extensionURL = try XCTUnwrap(context.optionsPageURL)
        var extensionLoadError: Error?

        adapter.loadURL(extensionURL, for: context) {
            extensionLoadError = $0
        }

        XCTAssertNil(extensionLoadError)
        XCTAssertEqual(browser.session.selectedTab?.url, extensionURL)
        let extensionPage = try XCTUnwrap(pages.activePage)
        XCTAssertFalse(extensionPage === standardPage)
        XCTAssertEqual(extensionPage.pendingNavigationURL, extensionURL)
        for _ in 0..<200 {
            let runtimeReady =
                try? await extensionPage.webView.evaluateJavaScript(
                    "document.documentElement.dataset.runtimeReady"
                ) as? String
            if runtimeReady == "true" {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        let runtimeReady =
            try await extensionPage.webView.evaluateJavaScript(
                "document.documentElement.dataset.runtimeReady"
            ) as? String
        XCTAssertEqual(runtimeReady, "true")
        XCTAssertNil(extensionPage.navigationFailure)

        let webURL = try XCTUnwrap(
            URL(string: "https://example.com/restored-standard-page")
        )
        var webLoadError: Error?

        adapter.loadURL(webURL, for: context) {
            webLoadError = $0
        }

        XCTAssertNil(webLoadError)
        XCTAssertEqual(browser.session.selectedTab?.url, webURL)
        XCTAssertTrue(pages.activePage === standardPage)
        XCTAssertEqual(standardPage.pendingNavigationURL, webURL)
    }

    func testExtensionPageReplacesItsRuntimeInTheExistingTabWithHistoryIntact()
        async throws
    {
        let tab = BrowserTab(
            title: "Routing",
            url: nil,
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Routing",
            symbol: "arrow.trianglehead.swap",
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
        var openedURL: URL?
        let pages = BrowserPagePool(
            monitorsMemoryPressure: false,
            extensionControllerPool: pool,
            openModifiedLink: { url, spaceID, selecting in
                openedURL = url
                browser.openNewTab(
                    url: url,
                    in: spaceID,
                    selecting: selecting
                )
            }
        )
        pool.connect(browser: browser, pageProvider: pages)
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        pages.select(session: browser.session)
        let standardPage = try XCTUnwrap(pages.activePage)
        let firstURL = try XCTUnwrap(
            URL(string: "https://example.com/extension-routing-first")
        )
        let secondURL = try XCTUnwrap(
            URL(string: "https://example.com/extension-routing-second")
        )
        try await load(firstURL, in: standardPage)
        try await load(secondURL, in: standardPage)
        browser.updateSelectedTabFromPage(url: secondURL, title: "Second")
        let adapter = try XCTUnwrap(
            pool.extensionTab(tab.id, in: space.id)
        )
        let extensionURL = try XCTUnwrap(context.optionsPageURL)
        var extensionLoadError: Error?

        adapter.loadURL(extensionURL, for: context) {
            extensionLoadError = $0
        }

        XCTAssertNil(extensionLoadError)
        XCTAssertEqual(browser.session.selectedTab?.id, tab.id)
        let extensionPage = try XCTUnwrap(pages.activePage)
        XCTAssertFalse(extensionPage === standardPage)
        XCTAssertTrue(pages.canGoBack)
        XCTAssertEqual(pages.backHistory.first?.url, secondURL)

        pages.goBack()

        XCTAssertTrue(pages.activePage === standardPage)
        XCTAssertEqual(pages.activePage?.webView.url, secondURL)
        XCTAssertTrue(pages.canGoForward)

        pages.goForward()

        XCTAssertTrue(pages.activePage === extensionPage)
        let destinationURL = try XCTUnwrap(
            URL(string: "https://example.com/crest-extension-location")
        )
        var runtimeReady = false
        for _ in 0..<200 where !runtimeReady {
            runtimeReady =
                (try? await extensionPage.webView.evaluateJavaScript(
                    "document.documentElement.dataset.runtimeReady"
                ) as? String) == "true"
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(runtimeReady)

        _ = try await extensionPage.webView.callAsyncJavaScript(
            """
            window.location.replace(destinationURL);
            return true;
            """,
            arguments: ["destinationURL": destinationURL.absoluteString],
            in: nil,
            contentWorld: .page
        )
        for _ in 0..<400 where pages.activePage !== standardPage {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertNil(extensionPage.navigationFailure)
        XCTAssertNil(openedURL)
        XCTAssertEqual(browser.session.selectedTab?.url, destinationURL)
        XCTAssertEqual(browser.session.selectedTab?.id, tab.id)
        XCTAssertTrue(pages.activePage === standardPage)
        XCTAssertTrue(standardPage.canGoBack)
        XCTAssertTrue(
            ["crest-extension", "webkit-extension"].contains(
                try XCTUnwrap(extensionPage.webView.url?.scheme)
            )
        )
    }

    func testAuditableManifestV3FixtureLoadsIntoIndependentSpaceContexts() async throws {
        let work = BrowserSession.preview.spaces[0]
        let personal = BrowserSession.preview.spaces[1]
        let pool = BrowserExtensionControllerPool()

        let workContext = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: work,
            unsupportedAPIs: ["browser.bookmarks"]
        )
        let personalContext = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: personal
        )

        XCTAssertTrue(workContext.isLoaded)
        XCTAssertTrue(personalContext.isLoaded)
        XCTAssertFalse(workContext === personalContext)
        XCTAssertNotEqual(workContext.uniqueIdentifier, personalContext.uniqueIdentifier)
        XCTAssertEqual(workContext.webExtension.displayName, "Crest Space Probe")
        XCTAssertEqual(workContext.webExtension.manifestVersion, 3)
        XCTAssertTrue(workContext.webExtension.requestedPermissions.contains(.storage))
        XCTAssertEqual(workContext.unsupportedAPIs, ["browser.bookmarks"])
        XCTAssertEqual(personalContext.unsupportedAPIs, [])
        XCTAssertTrue(workContext.webExtensionController === pool.controller(for: work))
        XCTAssertTrue(personalContext.webExtensionController === pool.controller(for: personal))
        XCTAssertEqual(pool.controller(for: work).extensionContexts.count, 1)
        XCTAssertEqual(pool.controller(for: personal).extensionContexts.count, 1)
        XCTAssertTrue(pool.loadedContext(extensionID: extensionID, in: work.id) === workContext)
        XCTAssertEqual(pool.extensions(in: work.id).map(\.displayName), ["Crest Space Probe"])
        XCTAssertEqual(pool.extensions(in: personal.id).map(\.displayName), ["Crest Space Probe"])
        XCTAssertEqual(
            pool.extensions(in: work.id).first?.requestedPermissions,
            ["activeTab", "storage"]
        )
        XCTAssertEqual(
            pool.extensions(in: work.id).first?.requestedHosts,
            ["https://extension-probe.crest.test/*"]
        )
    }

    func testPermissionDecisionsRemainIndependentAcrossSpaces() async throws {
        let work = BrowserSession.preview.spaces[0]
        let personal = BrowserSession.preview.spaces[1]
        let pool = BrowserExtensionControllerPool()
        let workContext = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: work
        )
        let personalContext = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: personal
        )

        workContext.setPermissionStatus(.grantedExplicitly, for: .storage)
        personalContext.setPermissionStatus(.deniedExplicitly, for: .storage)

        XCTAssertEqual(workContext.permissionStatus(for: .storage), .grantedExplicitly)
        XCTAssertEqual(personalContext.permissionStatus(for: .storage), .deniedExplicitly)
        XCTAssertTrue(workContext.hasPermission(.storage))
        XCTAssertFalse(personalContext.hasPermission(.storage))
    }

    func testLoadingTheSameExtensionTwiceInOneSpaceReusesItsContext() async throws {
        let space = BrowserSession.preview.spaces[0]
        let pool = BrowserExtensionControllerPool()

        let first = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        let second = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )

        XCTAssertTrue(first === second)
        XCTAssertEqual(pool.controller(for: space).extensionContexts.count, 1)
    }

    func testLoadingAnUnpackedExtensionStagesAndSummarizesItForOneSpace() async throws {
        let work = BrowserSession.preview.spaces[0]
        let personal = BrowserSession.preview.spaces[1]
        let pool = BrowserExtensionControllerPool()

        let summary = try await pool.loadUnpackedExtension(from: fixtureURL, in: work)

        XCTAssertEqual(summary.displayName, "Crest Space Probe")
        XCTAssertTrue(summary.id.hasPrefix("local."))
        XCTAssertTrue(summary.isLoaded)
        XCTAssertEqual(pool.extensions(in: work.id), [summary])
        XCTAssertTrue(pool.extensions(in: personal.id).isEmpty)
    }

    func testPinningALoadedToolbarActionUpdatesOnlyItsSpace() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-extension-pinning-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root
            ),
            registry: BrowserExtensionRegistry(persistence: persistence)
        )
        let work = BrowserSession.preview.spaces[0]
        let personal = BrowserSession.preview.spaces[1]
        let installed = try await pool.loadUnpackedExtension(
            from: fixtureURL,
            in: work
        )

        pool.setPinned(
            true,
            extensionID: installed.id,
            in: work.id
        )

        XCTAssertEqual(
            pool.extensions(in: work.id).first?.isPinned,
            true
        )
        XCTAssertEqual(
            pool.toolbarActions(in: work.id, tabID: nil).first?.isPinned,
            true
        )
        XCTAssertTrue(
            pool.toolbarActions(in: personal.id, tabID: nil).isEmpty
        )

        pool.setPinned(
            false,
            extensionID: installed.id,
            in: work.id
        )

        XCTAssertEqual(
            pool.toolbarActions(in: work.id, tabID: nil).first?.isPinned,
            false
        )
    }

    func testConfiguringAnExtensionCommandUpdatesOnlyItsSpace() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-extension-command-shortcuts-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root
            ),
            registry: BrowserExtensionRegistry()
        )
        let work = BrowserSession.preview.spaces[0]
        let personal = BrowserSession.preview.spaces[1]
        let workExtension = try await pool.loadUnpackedExtension(
            from: fixtureURL,
            in: work
        )
        _ = try await pool.loadUnpackedExtension(
            from: fixtureURL,
            in: personal
        )
        let custom = BrowserShortcut(
            key: .character("g"),
            modifiers: [.command, .option]
        )

        pool.setShortcut(
            custom,
            commandID: "addSite",
            extensionID: workExtension.id,
            in: work.id
        )

        XCTAssertEqual(
            pool.extensionCommands(in: work.id).first?.shortcut,
            custom
        )
        XCTAssertEqual(
            pool.extensionCommands(in: personal.id).first?.shortcut,
            BrowserShortcut(
                key: .character("a"),
                modifiers: [.option, .shift]
            )
        )
    }

    func testInstalledExtensionRestoresEnablementAndPermissionsAfterPoolReconstruction() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-pool-restoration-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? fileManager.removeItem(at: root) }
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let work = BrowserSession.preview.spaces[0]
        let hostPattern = try WKWebExtension.MatchPattern(
            string: "https://extension-probe.crest.test/*"
        )
        var extensionID = ""

        do {
            let pool = BrowserExtensionControllerPool(
                packageStore: BrowserExtensionPackageStore(
                    fileManager: fileManager,
                    rootURL: root,
                    removesRootOnDeinit: false
                ),
                registry: BrowserExtensionRegistry(
                    persistence: persistence
                )
            )
            let summary = try await pool.loadUnpackedExtension(
                from: fixtureURL,
                in: work
            )
            extensionID = summary.id
            let context = try XCTUnwrap(
                pool.loadedContext(
                    extensionID: extensionID,
                    in: work.id
                )
            )
            context.setPermissionStatus(
                .grantedExplicitly,
                for: .storage,
                expirationDate: .distantFuture
            )
            context.setPermissionStatus(
                .deniedExplicitly,
                for: .tabs,
                expirationDate: .distantFuture
            )
            context.setPermissionStatus(
                .grantedExplicitly,
                for: hostPattern,
                expirationDate: .distantFuture
            )
            pool.persistPermissionState(
                extensionID: extensionID,
                in: work.id
            )
        }

        let reconstructed = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root,
                removesRootOnDeinit: false
            ),
            registry: BrowserExtensionRegistry(
                persistence: persistence
            )
        )
        await reconstructed.restoreEnabledExtensions(in: [work])
        let restoredContext = try XCTUnwrap(
            reconstructed.loadedContext(
                extensionID: extensionID,
                in: work.id
            )
        )

        XCTAssertTrue(restoredContext.isLoaded)
        XCTAssertEqual(
            restoredContext.permissionStatus(for: .storage),
            .grantedExplicitly
        )
        XCTAssertEqual(
            restoredContext.permissionStatus(for: .tabs),
            .deniedExplicitly
        )
        XCTAssertEqual(
            restoredContext.permissionStatus(for: hostPattern),
            .grantedExplicitly
        )
    }

    func testDisabledExtensionRestoresAsVisibleButUnloaded() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-disabled-restoration-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? fileManager.removeItem(at: root) }
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let work = BrowserSession.preview.spaces[0]
        let installingPool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root,
                removesRootOnDeinit: false
            ),
            registry: BrowserExtensionRegistry(persistence: persistence)
        )
        let summary = try await installingPool.loadUnpackedExtension(
            from: fixtureURL,
            in: work
        )
        try await installingPool.setExtensionEnabled(
            false,
            extensionID: summary.id,
            in: work
        )
        let reconstructed = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root,
                removesRootOnDeinit: false
            ),
            registry: BrowserExtensionRegistry(persistence: persistence)
        )

        await reconstructed.restoreEnabledExtensions(in: [work])

        XCTAssertNil(
            reconstructed.loadedContext(
                extensionID: summary.id,
                in: work.id
            )
        )
        XCTAssertEqual(
            reconstructed.extensions(in: work.id).first?.isEnabled,
            false
        )
        XCTAssertEqual(
            reconstructed.extensions(in: work.id).first?.isLoaded,
            false
        )
    }

    func testRepeatedRestorationKeepsAnAlreadyLoadedExtensionReportedAsRunning() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-idempotent-restoration-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? fileManager.removeItem(at: root) }
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let work = BrowserSession.preview.spaces[0]
        let installingPool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root,
                removesRootOnDeinit: false
            ),
            registry: BrowserExtensionRegistry(persistence: persistence)
        )
        let installed = try await installingPool.loadUnpackedExtension(
            from: fixtureURL,
            in: work
        )

        await installingPool.restoreEnabledExtensions(in: [work])
        await installingPool.restoreEnabledExtensions(in: [work, work])

        let summary = try XCTUnwrap(
            installingPool.extensions(in: work.id).first {
                $0.id == installed.id
            }
        )
        XCTAssertTrue(summary.isEnabled)
        XCTAssertTrue(summary.isLoaded)
        XCTAssertNotNil(
            installingPool.loadedContext(
                extensionID: installed.id,
                in: work.id
            )
        )
    }

    func testPermissionChoicesCanBeEditedWhileAnExtensionIsDisabled() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-disabled-permissions-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? fileManager.removeItem(at: root) }
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let work = BrowserSession.preview.spaces[0]
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root,
                removesRootOnDeinit: false
            ),
            registry: BrowserExtensionRegistry(persistence: persistence)
        )
        let installed = try await pool.loadUnpackedExtension(
            from: fixtureURL,
            in: work
        )
        try await pool.setExtensionEnabled(
            false,
            extensionID: installed.id,
            in: work
        )

        pool.setPermissionDecision(
            .allow,
            for: "storage",
            extensionID: installed.id,
            in: work.id
        )
        pool.setHostDecision(
            .block,
            for: "https://extension-probe.crest.test/*",
            extensionID: installed.id,
            in: work.id
        )

        XCTAssertEqual(
            pool.permissionDecision(
                for: "storage",
                extensionID: installed.id,
                in: work.id
            ),
            .allow
        )
        XCTAssertEqual(
            pool.hostDecision(
                for: "https://extension-probe.crest.test/*",
                extensionID: installed.id,
                in: work.id
            ),
            .block
        )
        XCTAssertFalse(
            try XCTUnwrap(
                pool.extensions(in: work.id).first {
                    $0.id == installed.id
                }
            ).isLoaded
        )
    }

    func testPersistingPermissionChangesKeepsALoadedExtensionReportedAsRunning() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-live-permissions-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? fileManager.removeItem(at: root) }
        let work = BrowserSession.preview.spaces[0]
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root,
                removesRootOnDeinit: false
            ),
            registry: BrowserExtensionRegistry(
                persistence: InMemoryBrowserExtensionRegistryPersistence()
            )
        )
        let installed = try await pool.loadUnpackedExtension(
            from: fixtureURL,
            in: work
        )
        let context = try XCTUnwrap(
            pool.loadedContext(
                extensionID: installed.id,
                in: work.id
            )
        )

        context.setPermissionStatus(
            .grantedExplicitly,
            for: .storage,
            expirationDate: .distantFuture
        )
        pool.persistPermissionState(
            extensionID: installed.id,
            in: work.id
        )

        let summary = try XCTUnwrap(
            pool.extensions(in: work.id).first {
                $0.id == installed.id
            }
        )
        XCTAssertTrue(context.isLoaded)
        XCTAssertTrue(summary.isLoaded)
        XCTAssertEqual(
            pool.permissionDecision(
                for: "storage",
                extensionID: installed.id,
                in: work.id
            ),
            .allow
        )
    }

    func testRemovingAnExtensionFromOneSpaceLeavesAnotherSpacesInstallationRunning() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appending(
                path: "crest-extension-space-removal-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? fileManager.removeItem(at: root) }
        let persistence = InMemoryBrowserExtensionRegistryPersistence()
        let work = BrowserSession.preview.spaces[0]
        let personal = BrowserSession.preview.spaces[1]
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: root,
                removesRootOnDeinit: false
            ),
            registry: BrowserExtensionRegistry(persistence: persistence)
        )
        let workExtension = try await pool.loadUnpackedExtension(
            from: fixtureURL,
            in: work
        )
        let workContext = try XCTUnwrap(
            pool.loadedContext(
                extensionID: workExtension.id,
                in: work.id
            )
        )
        let personalExtension = try await pool.loadUnpackedExtension(
            from: fixtureURL,
            in: personal
        )
        let origin = URL(
            string: "https://extension-probe.crest.test/"
        )!
        workContext.setPermissionStatus(
            .grantedExplicitly,
            for: .storage
        )
        workContext.setPermissionStatus(
            .grantedExplicitly,
            for: origin
        )
        _ = try await loadProbePage(
            in: work,
            using: pool,
            origin: origin
        )
        try await pool.setExtensionEnabled(
            false,
            extensionID: workExtension.id,
            in: work
        )
        let dataTypes =
            WKWebExtensionController.allExtensionDataTypes
        let recordsBeforeRemoval =
            await pool
            .controller(for: work)
            .dataRecords(ofTypes: dataTypes)
        XCTAssertFalse(pool.controller(for: work).configuration.isPersistent)
        XCTAssertTrue(recordsBeforeRemoval.isEmpty)

        try await pool.removeExtension(
            extensionID: workExtension.id,
            from: work
        )

        XCTAssertTrue(pool.extensions(in: work.id).isEmpty)
        XCTAssertNil(
            pool.loadedContext(
                extensionID: workExtension.id,
                in: work.id
            )
        )
        let recordsAfterRemoval =
            await pool
            .controller(for: work)
            .dataRecords(ofTypes: dataTypes)
        XCTAssertTrue(recordsAfterRemoval.isEmpty)
        XCTAssertEqual(
            pool.extensions(in: personal.id).map(\.id),
            [personalExtension.id]
        )
        XCTAssertTrue(
            try XCTUnwrap(
                pool.loadedContext(
                    extensionID: personalExtension.id,
                    in: personal.id
                )
            ).isLoaded
        )
    }

    func testInjectedContentAndExtensionStorageRemainIndependentAcrossSpaces() async throws {
        let work = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let personal = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Personal",
            symbol: "person.fill",
            accent: .teal,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let pool = BrowserExtensionControllerPool()
        let origin = URL(string: "https://extension-probe.crest.test/")!
        let workContext = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: work
        )
        let personalContext = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: personal
        )

        for context in [workContext, personalContext] {
            context.setPermissionStatus(.grantedExplicitly, for: .storage)
            context.setPermissionStatus(.grantedExplicitly, for: origin)
        }

        let firstWorkVisit = try await loadProbePage(in: work, using: pool, origin: origin)
        let firstPersonalVisit = try await loadProbePage(in: personal, using: pool, origin: origin)
        let secondWorkVisit = try await loadProbePage(in: work, using: pool, origin: origin)

        XCTAssertEqual(firstWorkVisit.extensionID, workContext.uniqueIdentifier)
        XCTAssertEqual(firstPersonalVisit.extensionID, personalContext.uniqueIdentifier)
        XCTAssertEqual(firstWorkVisit.visitCount, 1)
        XCTAssertEqual(firstPersonalVisit.visitCount, 1)
        XCTAssertEqual(secondWorkVisit.visitCount, 2)
    }

    func testContentMessageIncludesOwningTabAndFrameMetadata() async throws {
        let browser = BrowserStore.preview()
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        let pool = BrowserExtensionControllerPool()
        let controller = pool.controller(for: space)
        let configuration = BrowserPageConfiguration.make(
            for: space.profile,
            webExtensionController: controller
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let pages = PageProviderSpy()
        pages.webViews[tab.id] = webView
        pool.connect(browser: browser, pageProvider: pages)
        let origin = try XCTUnwrap(
            URL(string: "https://extension-probe.crest.test/")
        )
        let context = try await pool.loadExtension(
            at: fixtureURL,
            extensionID: extensionID,
            in: space
        )
        context.setPermissionStatus(.grantedExplicitly, for: .storage)
        context.setPermissionStatus(.grantedExplicitly, for: origin)
        let waiter = ExtensionNavigationWaiter(webView: webView)

        try await waiter.load(
            simulatedRequest: URLRequest(url: origin),
            responseHTML: "<!doctype html><html><body>Sender probe</body></html>"
        )

        var response: [String: Any]?
        for _ in 0..<400 {
            if let encoded = try await webView.evaluateJavaScript(
                "document.documentElement.dataset.crestSenderResponse"
            ) as? String,
                let data = encoded.data(using: .utf8)
            {
                response =
                    try JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(response?["type"] as? String, "Success")
        let metadata = try XCTUnwrap(response?["data"] as? [String: Any])
        XCTAssertNotNil(metadata["tabID"] as? Int)
        XCTAssertEqual(metadata["frameID"] as? Int, 0)
    }

    func testCompatibilityBridgeUsesWebKitsContentTabIdentity() async throws {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-content-port-identity-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: extensionURL) }

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Content Port Identity Test",
            "description": "Measures WebKit message sender identity.",
            "version": "1.0",
            "permissions": ["storage", "tabs", "webNavigation"],
            "host_permissions": ["<all_urls>"],
            "background": [
                "service_worker": "background.js",
                "type": "module",
            ],
            "content_scripts": [
                [
                    "matches": ["<all_urls>"],
                    "js": ["content.js"],
                    "run_at": "document_start",
                ]
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        try Data(
            """
            chrome.runtime.onConnect.addListener((port) => {
                if (port.name === "crest-direct-port-probe") {
                    port.postMessage({
                        directConnectedTabID: port.sender?.tab?.id,
                        directConnectedFrameID: port.sender?.frameId,
                        directConnectedDocumentID: port.sender?.documentId,
                    });
                }
            });
            chrome.runtime.onMessage.addListener((message, sender, reply) => {
                if (message?.type !== "crest-content-port-identity") {
                    return false;
                }
                chrome.tabs.query(
                    { active: true, currentWindow: true },
                    (tabs) => {
                        const queriedTabID = tabs[0]?.id;
                        if (typeof queriedTabID !== "number") {
                            reply({
                                stage: "query-found-no-tab",
                                messageTabID: sender?.tab?.id,
                            });
                            return;
                        }
                        chrome.tabs.sendMessage(
                            queriedTabID,
                            { type: "crest-reverse-message" },
                            (reverseResponse) => reply({
                                stage: "background-received",
                                backgroundStorageSession:
                                    typeof browser.storage?.session?.get
                                        === "function",
                                backgroundOffscreen:
                                    typeof chrome.offscreen?.createDocument
                                        === "function",
                                backgroundOffscreenReason:
                                    chrome.offscreen?.Reason?.LOCAL_STORAGE,
                                backgroundClients:
                                    typeof globalThis.clients?.matchAll
                                        === "function",
                                backgroundCreatedNavigationTarget:
                                    typeof chrome.webNavigation
                                        ?.onCreatedNavigationTarget
                                        ?.addListener === "function",
                                queriedTabID,
                                messageTabID: sender?.tab?.id,
                                messageFrameID: sender?.frameId,
                                messageDocumentID: sender?.documentId,
                                reverseResponse: reverseResponse?.type,
                                reverseError:
                                    chrome.runtime.lastError?.message,
                            })
                        );
                    }
                );
                return true;
            });
            """.utf8
        ).write(to: extensionURL.appending(path: "background.js"))
        try Data(
            """
            const updateProbe = (value) => {
                const current = JSON.parse(
                    document.documentElement.dataset.crestPortIdentity ?? "{}"
                );
                document.documentElement.dataset.crestPortIdentity =
                    JSON.stringify({ ...current, ...value });
            };
            updateProbe({
                stage: "content-started",
                chromeRuntimeID: chrome.runtime.id,
                browserRuntimeID: browser.runtime.id,
                chromeManifestVersion:
                    chrome.runtime.getManifest().manifest_version,
                browserManifestVersion:
                    browser.runtime.getManifest().manifest_version,
                browserStorageLocal:
                    typeof browser.storage?.local?.get === "function",
                contentStorageSession:
                    typeof browser.storage?.session?.get === "function",
                browserStorageManaged:
                    typeof browser.storage?.managed?.onChanged?.addListener
                        === "function",
                wrappedJSObjectType: typeof globalThis.wrappedJSObject,
                wrappedSentinel:
                    globalThis.wrappedJSObject?.crestSentinel,
            });
            const directPort = chrome.runtime.connect({
                name: "crest-direct-port-probe",
            });
            directPort.onMessage.addListener((message) => updateProbe(message));
            directPort.onDisconnect.addListener(() => updateProbe({
                directDisconnected: true,
                directError: chrome.runtime.lastError?.message,
            }));
            chrome.runtime.onMessage.addListener((message, sender, reply) => {
                if (message?.type !== "crest-reverse-message") return false;
                updateProbe({
                    reverseResponse: "reverse-complete",
                    reverseSenderURL: sender?.url,
                });
                reply({ type: "reverse-complete" });
                return true;
            });
            chrome.runtime.sendMessage(
                { type: "crest-content-port-identity" },
                (response) => {
                    updateProbe(response ?? {
                        stage: "content-no-response",
                        error: chrome.runtime.lastError?.message,
                    });
                }
            );
            """.utf8
        ).write(to: extensionURL.appending(path: "content.js"))

        let browser = BrowserStore.preview()
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let tab = try XCTUnwrap(browser.session.selectedTab)
        let runtimeIdentity = BrowserExtensionRuntimeIdentity(
            extensionID: "content-port-identity",
            uniqueIdentifier: "content-port-identity.space.\(space.id)",
            baseURL: try XCTUnwrap(
                URL(string: "crest-extension://content-port-identity/")
            )
        )
        XCTAssertTrue(
            try BrowserWebExtensionCompatibilityPackagePreparer()
                .installCompatibilityLayer(
                    in: extensionURL,
                    requestedPermissions: ["storage", "tabs", "webNavigation"],
                    runtimeIdentity: runtimeIdentity
                )
        )
        let pool = BrowserExtensionControllerPool()
        let controller = pool.controller(for: space)
        let configuration = BrowserPageConfiguration.make(
            for: space.profile,
            webExtensionController: controller
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let pages = PageProviderSpy()
        pages.webViews[tab.id] = webView
        pool.connect(browser: browser, pageProvider: pages)
        let context = try await pool.loadExtension(
            at: extensionURL,
            extensionID: "content-port-identity",
            in: space
        )
        let origin = try XCTUnwrap(
            URL(string: "https://extension-probe.crest.test/")
        )
        context.setPermissionStatus(.grantedExplicitly, for: .storage)
        context.setPermissionStatus(.grantedExplicitly, for: .tabs)
        context.setPermissionStatus(.grantedExplicitly, for: origin)
        let waiter = ExtensionNavigationWaiter(webView: webView)
        try await waiter.load(
            simulatedRequest: URLRequest(url: origin),
            responseHTML: "<!doctype html><html><body>Port probe</body></html>"
        )

        var response: [String: Any]?
        for _ in 0..<400 {
            if let encoded = try await webView.evaluateJavaScript(
                "document.documentElement.dataset.crestPortIdentity"
            ) as? String,
                let data = encoded.data(using: .utf8)
            {
                response =
                    try JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
                if response?["reverseResponse"] as? String
                    == "reverse-complete",
                    response?["stage"] as? String == "background-received"
                {
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        let identity = try XCTUnwrap(
            response,
            "Content script did not start. Errors: \(context.errors)"
        )
        let contextErrorDescriptions = context.errors.map {
            let error = $0 as NSError
            return "\(error.domain)#\(error.code): \(error.localizedDescription)"
        }
        XCTAssertEqual(
            identity["stage"] as? String,
            "background-received",
            "Probe: \(identity); errors: \(contextErrorDescriptions)"
        )
        XCTAssertEqual(identity["queriedTabID"] as? Int, identity["messageTabID"] as? Int)
        XCTAssertEqual(identity["directConnectedTabID"] as? Int, identity["messageTabID"] as? Int)
        XCTAssertEqual(identity["directConnectedFrameID"] as? Int, 0)
        XCTAssertEqual(identity["messageFrameID"] as? Int, 0)
        XCTAssertEqual(
            identity["directConnectedDocumentID"] as? String,
            identity["messageDocumentID"] as? String
        )
        XCTAssertEqual(identity["reverseResponse"] as? String, "reverse-complete")
        XCTAssertNil(identity["reverseError"])
        XCTAssertEqual(identity["chromeManifestVersion"] as? Int, 3)
        XCTAssertEqual(identity["browserManifestVersion"] as? Int, 3)
        XCTAssertEqual(identity["browserStorageLocal"] as? Bool, true)
        XCTAssertEqual(identity["backgroundStorageSession"] as? Bool, true)
        XCTAssertEqual(identity["backgroundOffscreen"] as? Bool, true)
        XCTAssertEqual(
            identity["backgroundOffscreenReason"] as? String,
            "LOCAL_STORAGE"
        )
        XCTAssertEqual(identity["backgroundClients"] as? Bool, true)
        XCTAssertEqual(
            identity["backgroundCreatedNavigationTarget"] as? Bool,
            true
        )
        XCTAssertEqual(identity["contentStorageSession"] as? Bool, false)
        XCTAssertEqual(identity["browserStorageManaged"] as? Bool, true)
        XCTAssertEqual(identity["wrappedJSObjectType"] as? String, "object")
        XCTAssertNil(identity["wrappedSentinel"])
        XCTAssertNil(
            identity["error"],
            "Probe: \(identity); errors: \(contextErrorDescriptions)"
        )
    }

    func testGrantingRuntimeGatedAccessRestartsLoadedExtension()
        async throws
    {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-runtime-permission-probe-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let packageRoot = fileManager.temporaryDirectory.appending(
            path: "crest-runtime-permission-packages-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: extensionURL)
            try? fileManager.removeItem(at: packageRoot)
        }

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Runtime Permission Probe",
            "description": "Checks permission-gated extension namespaces.",
            "version": "1.0",
            "permissions": ["webRequest"],
            "host_permissions": ["<all_urls>"],
            "background": ["service_worker": "background.js"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: extensionURL.appending(path: "manifest.json")
        )
        try Data(
            """
            if (!chrome.webRequest?.onBeforeRedirect) {
                console.error("CREST_RUNTIME_PERMISSION_MISSING");
            } else {
                console.error("CREST_RUNTIME_PERMISSION_READY");
            }
            """.utf8
        ).write(to: extensionURL.appending(path: "background.js"))

        let space = BrowserSession.preview.spaces[0]
        let pool = BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore(
                fileManager: fileManager,
                rootURL: packageRoot,
                removesRootOnDeinit: false
            ),
            registry: BrowserExtensionRegistry(
                persistence: InMemoryBrowserExtensionRegistryPersistence()
            )
        )
        let installed = try await pool.loadUnpackedExtension(
            from: extensionURL,
            in: space
        )
        let originalContext = try XCTUnwrap(
            pool.loadedContext(extensionID: installed.id, in: space.id)
        )
        for _ in 0..<400
        where !originalContext.errors.contains(where: {
            $0.localizedDescription.contains(
                "CREST_RUNTIME_PERMISSION_MISSING"
            )
        }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(
            originalContext.errors.contains(where: {
                $0.localizedDescription.contains(
                    "CREST_RUNTIME_PERMISSION_MISSING"
                )
            })
        )

        try await pool.setPermissionDecision(
            .allow,
            for: "webRequest",
            extensionID: installed.id,
            in: space
        )
        try await pool.setHostDecision(
            .allow,
            for: try XCTUnwrap(installed.requestedHosts.first),
            extensionID: installed.id,
            in: space
        )

        let restartedContext = try XCTUnwrap(
            pool.loadedContext(extensionID: installed.id, in: space.id)
        )
        XCTAssertFalse(restartedContext === originalContext)
        for _ in 0..<400
        where !restartedContext.errors.contains(where: {
            $0.localizedDescription.contains("CREST_RUNTIME_PERMISSION_READY")
        }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(
            restartedContext.errors.contains(where: {
                $0.localizedDescription.contains(
                    "CREST_RUNTIME_PERMISSION_READY"
                )
            })
        )
        XCTAssertFalse(
            restartedContext.errors.contains(where: {
                $0.localizedDescription.contains(
                    "CREST_RUNTIME_PERMISSION_MISSING"
                )
            }),
            "A permission-granted restart still hid chrome.webRequest."
        )
    }

    private var extensionID: String {
        "com.pauldavis.crest.space-probe"
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/SpaceProbeExtension", directoryHint: .isDirectory)
    }

    private func loadProbePage(
        in space: BrowserSpace,
        using pool: BrowserExtensionControllerPool,
        origin: URL
    ) async throws -> (extensionID: String, visitCount: Int) {
        let configuration = BrowserPageConfiguration.make(
            for: space.profile,
            webExtensionController: pool.controller(for: space)
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = ExtensionNavigationWaiter(webView: webView)
        try await waiter.load(
            simulatedRequest: URLRequest(url: origin),
            responseHTML: "<!doctype html><html><body>Space probe</body></html>"
        )

        // A cold extension WebContent process can materialize several seconds
        // behind ordinary page processes when the complete WebKit suite runs.
        // Keep polling the same observable contract without weakening it.
        for _ in 0..<400 {
            let value = try await webView.callAsyncJavaScript(
                """
                const root = document.documentElement.dataset;
                if (!root.crestExtensionID || !root.crestVisitCount) return null;
                return `${root.crestExtensionID}|${root.crestVisitCount}`;
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            if let encoded = value as? String {
                let pieces = encoded.split(separator: "|", maxSplits: 1).map(String.init)
                return (
                    extensionID: try XCTUnwrap(pieces.first),
                    visitCount: try XCTUnwrap(Int(try XCTUnwrap(pieces.last)))
                )
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTFail("The MV3 content script did not expose its Space-local state.")
        throw BrowserExtensionFixtureError.injectionTimedOut
    }

    private func load(_ url: URL, in page: BrowserPage) async throws {
        page.webView.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        page.webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: "<!doctype html><html><body>\(url.path)</body></html>"
        )
        for attempt in 0..<200 {
            if page.webView.url == url, !page.webView.isLoading {
                return
            }
            if attempt < 199 {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        XCTFail("Timed out loading \(url).")
    }
}

@MainActor
private final class NativeMessagingHandlerSpy:
    BrowserExtensionNativeMessagingHandling
{
    let capability = BrowserExtensionNativeMessagingCapability.available
    let receivedMessage = XCTestExpectation(
        description: "WebKit native messaging delegate"
    )
    private(set) var message: Any?
    private(set) var hostName: String?
    private(set) var extensionID: BrowserChromeExtensionID?
    private(set) var extensionIdentity: BrowserExtensionNativeMessagingIdentity?
    private(set) var authorization: BrowserExtensionNativeMessagingAuthorization?

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        self.message = message
        hostName = applicationIdentifier
        self.extensionIdentity = extensionIdentity
        self.authorization = authorization
        if case .chromeWebStore(let extensionID) = extensionIdentity {
            self.extensionID = extensionID
        }
        replyHandler(["received": true], nil)
        receivedMessage.fulfill()
    }

    func connect(
        port _: WKWebExtension.MessagePort,
        extensionIdentity _: BrowserExtensionNativeMessagingIdentity,
        authorization _: BrowserExtensionNativeMessagingAuthorization,
        completionHandler: @escaping (Error?) -> Void
    ) {
        completionHandler(nil)
    }
}

@MainActor
private final class IdleCapabilityBrokerHandler:
    BrowserExtensionNativeMessagingHandling
{
    let capability = BrowserExtensionNativeMessagingCapability.available
    let receivedState = XCTestExpectation(
        description: "Mapped idle state change"
    )
    private let broker = BrowserNativeMessagingService(
        capability: .available,
        resolver: BrowserNativeMessagingHostManifestResolver(
            searchDirectories: []
        ),
        idleStateProvider: { _ in .idle }
    )
    private(set) var hostName: String?
    private(set) var state: String?
    private(set) var authorization: BrowserExtensionNativeMessagingAuthorization?

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        if applicationIdentifier
            == BrowserNativeMessagingService.capabilityBrokerIdentifier
        {
            broker.sendMessage(
                message,
                applicationIdentifier: applicationIdentifier,
                extensionIdentity: extensionIdentity,
                authorization: authorization,
                replyHandler: replyHandler
            )
            return
        }
        hostName = applicationIdentifier
        state = (message as? [String: Any])?["state"] as? String
        self.authorization = authorization
        replyHandler(["received": true], nil)
        receivedState.fulfill()
    }

    func connect(
        port: WKWebExtension.MessagePort,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        completionHandler: @escaping (Error?) -> Void
    ) {
        broker.connect(
            port: port,
            extensionIdentity: extensionIdentity,
            authorization: authorization,
            completionHandler: completionHandler
        )
    }
}

@MainActor
private final class NotificationCapabilityBrokerHandler:
    BrowserExtensionNativeMessagingHandling
{
    let capability = BrowserExtensionNativeMessagingCapability.available
    let createdNotification = XCTestExpectation(
        description: "Mapped notification created"
    )
    let receivedClick = XCTestExpectation(
        description: "Mapped notification click"
    )
    private let center = InMemoryBrowserExtensionNotificationCenter()
    private lazy var broker = BrowserNativeMessagingService(
        capability: .available,
        resolver: BrowserNativeMessagingHostManifestResolver(
            searchDirectories: []
        ),
        notificationService: BrowserExtensionNotificationService(
            center: center
        ),
        idleStateProvider: { _ in .active }
    )
    private(set) var clickedIdentifier: String?
    private(set) var authorization: BrowserExtensionNativeMessagingAuthorization?

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        if applicationIdentifier
            == BrowserNativeMessagingService.capabilityBrokerIdentifier
        {
            broker.sendMessage(
                message,
                applicationIdentifier: applicationIdentifier,
                extensionIdentity: extensionIdentity,
                authorization: authorization
            ) { [weak self] value, error in
                if (message as? [String: Any])?["api"] as? String
                    == "notifications.create"
                {
                    self?.createdNotification.fulfill()
                }
                replyHandler(value, error)
            }
            return
        }
        clickedIdentifier =
            (message as? [String: Any])?["identifier"] as? String
        self.authorization = authorization
        replyHandler(["received": true], nil)
        receivedClick.fulfill()
    }

    func connect(
        port: WKWebExtension.MessagePort,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        completionHandler: @escaping (Error?) -> Void
    ) {
        broker.connect(
            port: port,
            extensionIdentity: extensionIdentity,
            authorization: authorization,
            completionHandler: completionHandler
        )
    }

    func simulateClick() throws {
        let systemIdentifier = try XCTUnwrap(
            center.deliveries.first?.systemIdentifier
        )
        center.simulate(
            BrowserExtensionNotificationSystemEvent(
                systemIdentifier: systemIdentifier,
                kind: .clicked
            )
        )
    }
}

@MainActor
private final class ExtensionNavigationWaiter: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func load(simulatedRequest request: URLRequest, responseHTML: String) async throws {
        guard let webView else { throw BrowserExtensionFixtureError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadSimulatedRequest(request, responseHTML: responseHTML)
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

private enum BrowserExtensionFixtureError: Error {
    case injectionTimedOut
    case releasedWebView
}
