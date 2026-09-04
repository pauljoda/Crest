import Network
import XCTest

@testable import Crest

final class BrowserNativeMessagingTests: XCTestCase {
    @MainActor
    func testCapabilityBrokerDisconnectRetainsContextMenuDefinitions() throws {
        let clientID = try XCTUnwrap(
            BrowserExtensionServiceClientID("extension.space")
        )
        let registry = BrowserExtensionWebpageMenuRegistry()
        var publishedMessages: [[String: Any]] = []
        let connection = BrowserExtensionCapabilityBrokerConnection(
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: ["contextMenus"],
                clientID: clientID
            ),
            notificationService: nil,
            idleStateProvider: { _ in .active },
            webpageMenuRegistry: registry,
            publish: { publishedMessages.append($0) }
        )
        try connection.receive([
            "api": "contextMenus.replace",
            "items": [
                [
                    "id": "page",
                    "type": "normal",
                    "title": "Page",
                    "contexts": ["page"],
                    "documentUrlPatterns": [],
                    "targetUrlPatterns": [],
                    "enabled": true,
                    "visible": true,
                ] as [String: Any]
            ],
        ])

        connection.stop()

        XCTAssertEqual(registry.definitions(for: clientID).map(\.id), ["page"])
        registry.publishClick(
            menuItemID: "page",
            context: BrowserExtensionWebpageMenuContext(
                pageURL: URL(string: "https://example.com")!,
                documentURL: URL(string: "https://example.com")!,
                linkURL: nil,
                sourceURL: nil,
                selectionText: nil,
                isEditable: false,
                isMainFrame: true
            ),
            for: clientID
        )
        XCTAssertTrue(publishedMessages.isEmpty)
    }

    @MainActor
    func testCapabilityBrokerRehydratesContextMenusAfterWorkerRestart() throws {
        let clientID = try XCTUnwrap(
            BrowserExtensionServiceClientID("extension.space")
        )
        let registry = BrowserExtensionWebpageMenuRegistry()
        try registry.replaceDefinitions(
            message: [
                "api": "contextMenus.replace",
                "items": [
                    [
                        "id": "string:image",
                        "type": "normal",
                        "title": "Image",
                        "contexts": ["image"],
                        "documentUrlPatterns": ["https://example.com/*"],
                        "targetUrlPatterns": ["https://cdn.example.com/*"],
                        "enabled": true,
                        "visible": true,
                    ] as [String: Any]
                ],
            ],
            for: clientID
        )
        var publishedMessages: [[String: Any]] = []
        let connection = BrowserExtensionCapabilityBrokerConnection(
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: ["contextMenus"],
                clientID: clientID
            ),
            notificationService: nil,
            idleStateProvider: { _ in .active },
            webpageMenuRegistry: registry,
            publish: { publishedMessages.append($0) }
        )
        registry.publishClick(
            menuItemID: "string:image",
            context: BrowserExtensionWebpageMenuContext(
                pageURL: URL(string: "https://example.com/article")!,
                documentURL: URL(string: "https://example.com/article")!,
                linkURL: nil,
                sourceURL: URL(string: "https://cdn.example.com/photo.webp")!,
                mediaType: .image,
                selectionText: nil,
                isEditable: false,
                isMainFrame: true
            ),
            for: clientID
        )

        try connection.receive(["api": "contextMenus.ready"])

        let restoration = try XCTUnwrap(
            publishedMessages.first { $0["api"] as? String == "contextMenus.restore" }
        )
        let items = try XCTUnwrap(restoration["items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["id"] as? String, "string:image")
        XCTAssertEqual(items.first?["contexts"] as? [String], ["image"])
        XCTAssertEqual(
            items.first?["targetUrlPatterns"] as? [String],
            ["https://cdn.example.com/*"]
        )
        XCTAssertEqual(
            publishedMessages.compactMap { $0["api"] as? String },
            ["contextMenus.restore", "contextMenus.click"]
        )
        XCTAssertEqual(
            publishedMessages.last?["mediaType"] as? String,
            "image"
        )
    }

    @MainActor
    func testCrestCapabilityBrokerAnswersIdleStateWithoutAnExternalHost()
        async throws
    {
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        var receivedInterval: TimeInterval?
        let service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: []
            ),
            idleStateProvider: { interval in
                receivedInterval = interval
                return .idle
            }
        )
        let response = expectation(description: "Crest capability response")
        var received: Any?
        var receivedError: Error?

        service.sendMessage(
            [
                "api": "idle.queryState",
                "detectionIntervalInSeconds": 300,
            ],
            applicationIdentifier:
                "com.pauldavis.crest.webextension-compatibility",
            extensionIdentity: .chromeWebStore(extensionID),
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: ["idle"],
                allowsInternalCapabilityBroker: true
            )
        ) { value, error in
            received = value
            receivedError = error
            response.fulfill()
        }
        await fulfillment(of: [response], timeout: 1)

        XCTAssertNil(receivedError)
        XCTAssertEqual(receivedInterval, 300)
        XCTAssertEqual(
            (received as? [String: String])?["state"],
            "idle"
        )
    }

    @MainActor
    func testCrestCapabilityBrokerRequiresTheMappedExtensionPermission()
        async throws
    {
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: []
            ),
            idleStateProvider: { _ in .active }
        )
        let response = expectation(description: "Denied capability response")
        var received: Any?
        var receivedError: Error?

        service.sendMessage(
            [
                "api": "idle.queryState",
                "detectionIntervalInSeconds": 300,
            ],
            applicationIdentifier:
                "com.pauldavis.crest.webextension-compatibility",
            extensionIdentity: .chromeWebStore(extensionID),
            authorization: BrowserExtensionNativeMessagingAuthorization(
                allowsInternalCapabilityBroker: true
            )
        ) { value, error in
            received = value
            receivedError = error
            response.fulfill()
        }
        await fulfillment(of: [response], timeout: 1)

        XCTAssertNil(received)
        XCTAssertEqual(
            receivedError as? BrowserExtensionCapabilityBrokerError,
            .permissionDenied("idle")
        )
    }

    @MainActor
    func testContextMenuTransportCannotReachAnExternalNativeHost()
        async throws
    {
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: []
            )
        )
        let response = expectation(description: "Rejected external host")
        var receivedError: Error?

        service.sendMessage(
            ["ping": "pong"],
            applicationIdentifier: "com.example.native-host",
            extensionIdentity: .chromeWebStore(extensionID),
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: ["contextMenus"],
                allowsInternalCapabilityBroker: true
            )
        ) { _, error in
            receivedError = error
            response.fulfill()
        }
        await fulfillment(of: [response], timeout: 1)

        guard
            case .permissionDenied("nativeMessaging")? =
                receivedError as? BrowserExtensionCapabilityBrokerError
        else {
            return XCTFail("The internal menu transport reached an external host.")
        }
    }

    /// Diagnostics are telemetry from the extension's own code, not a
    /// capability: the report is the extension's own error text, and gating it
    /// behind a permission would silence exactly the extensions whose failures
    /// are hardest to see. An authorized broker context is the whole gate.
    @MainActor
    func testDiagnosticsReportIsRecordedWithoutAnyPermissionGrant()
        async throws
    {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-diagnostics-extension-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: extensionURL) }
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 3,
                "name": "Diagnostics Reporter",
                "version": "1.0",
            ] as [String: Any]
        ).write(to: extensionURL.appending(path: "manifest.json"))
        try Data("void 0;".utf8).write(
            to: extensionURL.appending(path: "background.js")
        )
        // A fresh identifier per run keeps this test's entries out of every
        // other context's ring in the process-wide diagnostics log.
        let extensionID = "diagnostics-\(UUID().uuidString.lowercased())"
        let pool = BrowserExtensionControllerPool()
        let browser = BrowserStore.preview()
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: extensionURL,
            extensionID: extensionID,
            in: space
        )
        pool.tabWindowCoordinator.registerCapabilityBrokerAuthorization(
            BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: [],
                clientID: .scoped(
                    extensionID: extensionID,
                    spaceID: space.id
                ),
                allowsInternalCapabilityBroker: true
            ),
            for: context
        )

        var value: Any?
        var error: Error?
        let recordedReply = expectation(description: "Diagnostics reply")
        pool.tabWindowCoordinator.webExtensionController(
            pool.controller(for: space),
            sendMessage: [
                "api": "diagnostics.report",
                "kind": "error",
                "message": "TypeError: undefined is not an object",
                "stack": "at popup.js:12",
                "source": context.baseURL.absoluteString
                    + "popup.html?token=secret#state",
                "lineno": 12,
                "colno": 7,
                "at": 1,
            ],
            toApplicationWithIdentifier:
                BrowserExtensionNativeMessagingApplication
                .capabilityBrokerIdentifier,
            for: context
        ) { replyValue, replyError in
            value = replyValue
            error = replyError
            recordedReply.fulfill()
        }
        await fulfillment(of: [recordedReply], timeout: 2)

        XCTAssertNil(error)
        XCTAssertEqual((value as? [String: Bool])?["recorded"], true)
        let summary = pool.runtimeContextController.summary(
            for: context,
            extensionID: extensionID,
            isEnabled: true
        )
        let recorded = try XCTUnwrap(
            summary.errors.first {
                $0.contains("undefined is not an object")
            },
            "A reported fault belongs in the extension's Needs attention list."
        )
        XCTAssertTrue(recorded.hasPrefix("Uncaught error at "))
        XCTAssertTrue(recorded.contains("popup.html:12:7"))
        XCTAssertFalse(
            recorded.contains("token=secret") || recorded.contains("#state"),
            """
            An extension page's query and fragment can carry a page URL, an
            account name, or a one-time token. Only the path is recorded.
            """
        )
        XCTAssertTrue(summary.needsAttention)

        // Console output is routine even in a healthy extension, so it is
        // logged and left out of the errors a person is asked to act on.
        var consoleValue: Any?
        var consoleError: Error?
        let consoleReply = expectation(description: "Console reply")
        pool.tabWindowCoordinator.webExtensionController(
            pool.controller(for: space),
            sendMessage: [
                "api": "diagnostics.report",
                "kind": "console",
                "level": "warn",
                "message":
                    "[BrowserApi] Message sender is not from the top frame",
                "source": context.baseURL.absoluteString + "popup.html",
                "at": 2,
            ],
            toApplicationWithIdentifier:
                BrowserExtensionNativeMessagingApplication
                .capabilityBrokerIdentifier,
            for: context
        ) { replyValue, replyError in
            consoleValue = replyValue
            consoleError = replyError
            consoleReply.fulfill()
        }
        await fulfillment(of: [consoleReply], timeout: 2)
        XCTAssertNil(consoleError)
        XCTAssertEqual((consoleValue as? [String: Bool])?["recorded"], true)
        XCTAssertEqual(
            pool.runtimeContextController.summary(
                for: context,
                extensionID: extensionID,
                isEnabled: true
            ).errors,
            summary.errors
        )
    }

    /// A context Crest never authorized for its broker cannot file reports
    /// against a verified extension.
    @MainActor
    func testDiagnosticsReportFromAnUnauthorizedContextIsRefused()
        async throws
    {
        let fileManager = FileManager.default
        let extensionURL = fileManager.temporaryDirectory.appending(
            path: "crest-diagnostics-unauthorized-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extensionURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: extensionURL) }
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 3,
                "name": "Unauthorized Reporter",
                "version": "1.0",
            ] as [String: Any]
        ).write(to: extensionURL.appending(path: "manifest.json"))
        let extensionID = "diagnostics-\(UUID().uuidString.lowercased())"
        let pool = BrowserExtensionControllerPool()
        let browser = BrowserStore.preview()
        let space = try XCTUnwrap(browser.session.selectedSpace)
        let context = try await pool.loadExtension(
            at: extensionURL,
            extensionID: extensionID,
            in: space
        )

        var value: Any?
        var error: Error?
        let refusedReply = expectation(description: "Refused diagnostics reply")
        pool.tabWindowCoordinator.webExtensionController(
            pool.controller(for: space),
            sendMessage: [
                "api": "diagnostics.report",
                "kind": "error",
                "message": "forged",
            ],
            toApplicationWithIdentifier:
                BrowserExtensionNativeMessagingApplication
                .capabilityBrokerIdentifier,
            for: context
        ) { replyValue, replyError in
            value = replyValue
            error = replyError
            refusedReply.fulfill()
        }
        await fulfillment(of: [refusedReply], timeout: 2)

        XCTAssertNil(value)
        XCTAssertEqual(
            error as? BrowserExtensionNativeMessagingError,
            .unverifiedExtension
        )
        XCTAssertTrue(
            pool.runtimeContextController.summary(
                for: context,
                extensionID: extensionID,
                isEnabled: true
            ).errors.allSatisfy { !$0.contains("forged") }
        )
    }

    @MainActor
    func testCapabilityBrokerAnswersInASandboxedBuild() async throws {
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let service = BrowserNativeMessagingService(
            capability: .unavailableInAppSandbox,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: []
            ),
            idleStateProvider: { _ in .locked }
        )
        let response = expectation(description: "Sandboxed broker response")
        var received: Any?
        var receivedError: Error?

        service.sendMessage(
            [
                "api": "idle.queryState",
                "detectionIntervalInSeconds": 60,
            ],
            applicationIdentifier:
                "com.pauldavis.crest.webextension-compatibility",
            extensionIdentity: .chromeWebStore(extensionID),
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: ["idle"],
                allowsInternalCapabilityBroker: true
            )
        ) { value, error in
            received = value
            receivedError = error
            response.fulfill()
        }
        await fulfillment(of: [response], timeout: 1)

        XCTAssertNil(receivedError)
        XCTAssertEqual(
            (received as? [String: String])?["state"],
            "locked",
            "The in-process broker spawns nothing, so App Sandbox cannot stop it."
        )
    }

    @MainActor
    func testExternalNativeHostStaysUnavailableInASandboxedBuild()
        async throws
    {
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let service = BrowserNativeMessagingService(
            capability: .unavailableInAppSandbox,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: []
            )
        )
        let response = expectation(description: "Rejected external host")
        var received: Any?
        var receivedError: Error?

        service.sendMessage(
            ["ping": "pong"],
            applicationIdentifier: "com.example.native-host",
            extensionIdentity: .chromeWebStore(extensionID),
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: ["nativeMessaging"],
                allowsInternalCapabilityBroker: true
            )
        ) { value, error in
            received = value
            receivedError = error
            response.fulfill()
        }
        await fulfillment(of: [response], timeout: 1)

        XCTAssertNil(received)
        guard
            case .unavailable? =
                receivedError as? BrowserExtensionNativeMessagingError
        else {
            return XCTFail(
                "A sandboxed build must still refuse to launch a native host."
            )
        }
    }

    @MainActor
    func testIdleWatchPublishesOnlyRealStateTransitions() throws {
        var sampledInterval: TimeInterval?
        var sampledState = BrowserExtensionSystemIdleState.active
        var publishedStates: [String] = []
        let watch = BrowserExtensionIdleWatch(
            stateProvider: { interval in
                sampledInterval = interval
                return sampledState
            },
            publish: { message in
                if let state = message["state"] as? String {
                    publishedStates.append(state)
                }
            }
        )

        try watch.configure(
            [
                "api": "idle.watch",
                "detectionIntervalInSeconds": 45,
            ]
        )
        XCTAssertEqual(sampledInterval, 45)
        XCTAssertEqual(publishedStates, ["active"])

        watch.publishCurrentState()
        XCTAssertEqual(publishedStates, ["active"])

        sampledState = .idle
        watch.publishCurrentState()
        XCTAssertEqual(publishedStates, ["active", "idle"])

        sampledState = .locked
        watch.publishCurrentState()
        XCTAssertEqual(publishedStates, ["active", "idle", "locked"])
    }

    @MainActor
    func testCrestCapabilityBrokerRoutesNotificationsByVerifiedClient()
        async throws
    {
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let clientID = try XCTUnwrap(
            BrowserExtensionServiceClientID("extension.space")
        )
        let center = InMemoryBrowserExtensionNotificationCenter()
        let notificationService = BrowserExtensionNotificationService(
            center: center
        )
        let service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: []
            ),
            notificationService: notificationService,
            idleStateProvider: { _ in .active }
        )
        let response = expectation(description: "Notification response")
        var received: Any?
        var receivedError: Error?

        service.sendMessage(
            [
                "api": "notifications.create",
                "notificationIdentifier": "saved-item",
                "title": "Saved",
                "message": "The login was saved.",
                "buttonTitles": ["Open"],
            ],
            applicationIdentifier:
                BrowserNativeMessagingService.capabilityBrokerIdentifier,
            extensionIdentity: .chromeWebStore(extensionID),
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: ["notifications"],
                clientID: clientID,
                allowsInternalCapabilityBroker: true
            )
        ) { value, error in
            received = value
            receivedError = error
            response.fulfill()
        }
        await fulfillment(of: [response], timeout: 1)

        XCTAssertNil(receivedError)
        XCTAssertEqual(
            (received as? [String: Any])?["notificationIdentifier"] as? String,
            "saved-item"
        )
        let delivery = try XCTUnwrap(center.deliveries.first)
        XCTAssertEqual(delivery.title, "Saved")
        XCTAssertEqual(delivery.body, "The login was saved.")
        XCTAssertEqual(delivery.buttonTitles, ["Open"])
        XCTAssertEqual(
            delivery.threadIdentifier,
            BrowserExtensionNotificationIdentityCodec.threadIdentifier(
                for: clientID
            )
        )
    }

    @MainActor
    func testCrestCapabilityBrokerSupportsTheNotificationLifecycle()
        async throws
    {
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let clientID = try XCTUnwrap(
            BrowserExtensionServiceClientID("extension.space")
        )
        let center = InMemoryBrowserExtensionNotificationCenter()
        let notificationService = BrowserExtensionNotificationService(
            center: center
        )
        let service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: []
            ),
            notificationService: notificationService,
            idleStateProvider: { _ in .active }
        )
        let authorization = BrowserExtensionNativeMessagingAuthorization(
            grantedPermissions: ["notifications"],
            clientID: clientID,
            allowsInternalCapabilityBroker: true
        )

        let create = await capabilityResponse(
            from: service,
            message: [
                "api": "notifications.create",
                "notificationIdentifier": "saved-item",
                "title": "Saved",
                "message": "The login was saved.",
                "buttonTitles": ["Open"],
            ],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(create.error)

        let getAll = await capabilityResponse(
            from: service,
            message: ["api": "notifications.getAll"],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(getAll.error)
        XCTAssertEqual(
            (getAll.value as? [String: Any])?["notificationIdentifiers"]
                as? [String],
            ["saved-item"]
        )

        let permission = await capabilityResponse(
            from: service,
            message: ["api": "notifications.getPermissionLevel"],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(permission.error)
        XCTAssertEqual(
            (permission.value as? [String: String])?["level"],
            "granted"
        )

        let update = await capabilityResponse(
            from: service,
            message: [
                "api": "notifications.update",
                "notificationIdentifier": "saved-item",
                "title": "Updated",
                "message": "The login changed.",
                "buttonTitles": [],
            ],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(update.error)
        XCTAssertEqual(
            (update.value as? [String: Bool])?["updated"],
            true
        )
        XCTAssertEqual(center.deliveries.first?.title, "Updated")

        let missingUpdate = await capabilityResponse(
            from: service,
            message: [
                "api": "notifications.update",
                "notificationIdentifier": "missing",
                "title": "Missing",
                "message": "Not presented.",
                "buttonTitles": [],
            ],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(missingUpdate.error)
        XCTAssertEqual(
            (missingUpdate.value as? [String: Bool])?["updated"],
            false
        )

        let clear = await capabilityResponse(
            from: service,
            message: [
                "api": "notifications.clear",
                "notificationIdentifier": "saved-item",
            ],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(clear.error)
        XCTAssertEqual(
            (clear.value as? [String: Bool])?["cleared"],
            true
        )
        XCTAssertTrue(center.deliveries.isEmpty)

        let clearAgain = await capabilityResponse(
            from: service,
            message: [
                "api": "notifications.clear",
                "notificationIdentifier": "saved-item",
            ],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(clearAgain.error)
        XCTAssertEqual(
            (clearAgain.value as? [String: Bool])?["cleared"],
            false
        )
    }

    /// `chrome.notifications.update` is a partial edit: an extension that
    /// sends only a new message must not blank the title and the buttons its
    /// notification is showing, and an identifier it never posted answers
    /// `false` instead of creating one.
    @MainActor
    func testCrestCapabilityBrokerMergesAPartialNotificationUpdate()
        async throws
    {
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let clientID = try XCTUnwrap(
            BrowserExtensionServiceClientID("extension.space")
        )
        let center = InMemoryBrowserExtensionNotificationCenter()
        let service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: []
            ),
            notificationService: BrowserExtensionNotificationService(
                center: center
            ),
            idleStateProvider: { _ in .active }
        )
        let authorization = BrowserExtensionNativeMessagingAuthorization(
            grantedPermissions: ["notifications"],
            clientID: clientID,
            allowsInternalCapabilityBroker: true
        )

        let create = await capabilityResponse(
            from: service,
            message: [
                "api": "notifications.create",
                "notificationIdentifier": "sync",
                "title": "Syncing",
                "message": "Ten percent.",
                "buttonTitles": ["Pause", "Cancel"],
            ],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(create.error)

        let messageOnly = await capabilityResponse(
            from: service,
            message: [
                "api": "notifications.update",
                "notificationIdentifier": "sync",
                "message": "Ninety percent.",
            ],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(messageOnly.error)
        XCTAssertEqual(
            (messageOnly.value as? [String: Bool])?["updated"],
            true
        )
        XCTAssertEqual(center.deliveries.count, 1)
        XCTAssertEqual(center.deliveries.first?.title, "Syncing")
        XCTAssertEqual(center.deliveries.first?.body, "Ninety percent.")
        XCTAssertEqual(
            center.deliveries.first?.buttonTitles,
            ["Pause", "Cancel"]
        )

        // An explicit null reads the same as an omitted field: keep.
        let nullTitle = await capabilityResponse(
            from: service,
            message: [
                "api": "notifications.update",
                "notificationIdentifier": "sync",
                "title": NSNull(),
                "buttonTitles": ["Resume"],
            ],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(nullTitle.error)
        XCTAssertEqual(
            (nullTitle.value as? [String: Bool])?["updated"],
            true
        )
        XCTAssertEqual(center.deliveries.first?.title, "Syncing")
        XCTAssertEqual(center.deliveries.first?.buttonTitles, ["Resume"])

        let unknown = await capabilityResponse(
            from: service,
            message: [
                "api": "notifications.update",
                "notificationIdentifier": "never-posted",
                "message": "Nothing to edit.",
            ],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNil(unknown.error)
        XCTAssertEqual(
            (unknown.value as? [String: Bool])?["updated"],
            false
        )
        XCTAssertEqual(center.deliveries.count, 1)

        // A field that is present with the wrong type is still malformed.
        let malformed = await capabilityResponse(
            from: service,
            message: [
                "api": "notifications.update",
                "notificationIdentifier": "sync",
                "message": 7,
            ],
            extensionID: extensionID,
            authorization: authorization
        )
        XCTAssertNotNil(malformed.error)
    }

    @MainActor
    func testMacBuildExchangesAFramedMessageWithACompanionProcess()
        async throws
    {
        guard
            BrowserPlatformExtensionNativeMessagingCapability.currentBuild
                == .available
        else {
            throw XCTSkip("This build cannot launch native hosts.")
        }
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-native-transport-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            ))
        let hostName = "com.example.echo"
        let executable = root.appending(path: "echo-host.py")
        let script = """
            #!/usr/bin/python3
            import json, struct, sys
            header = sys.stdin.buffer.read(4)
            size = struct.unpack('<I', header)[0]
            message = json.loads(sys.stdin.buffer.read(size))
            payload = json.dumps({'echo': message}).encode('utf-8')
            sys.stdout.buffer.write(struct.pack('<I', len(payload)) + payload)
            sys.stdout.buffer.flush()
            """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let manifest: [String: Any] = [
            "name": hostName,
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://\(extensionID.rawValue)/"
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appending(path: "\(hostName).json")
        )
        let service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: [root]
            )
        )
        let response = expectation(description: "Native host response")
        var received: Any?
        var receivedError: Error?

        service.sendMessage(
            ["ping": "pong"],
            applicationIdentifier: hostName,
            extensionID: extensionID
        ) { value, error in
            received = value
            receivedError = error
            response.fulfill()
        }
        await fulfillment(of: [response], timeout: 5)

        XCTAssertNil(receivedError)
        let echo =
            (received as? [String: Any])?["echo"]
            as? [String: String]
        XCTAssertEqual(echo?["ping"], "pong")
    }

    @MainActor
    func testFirefoxServiceLaunchesAHostWithItsPublishedArguments()
        async throws
    {
        guard
            BrowserPlatformExtensionNativeMessagingCapability.currentBuild
                == .available
        else {
            throw XCTSkip("This build cannot launch native hosts.")
        }
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-firefox-native-transport-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let extensionID = try XCTUnwrap(
            BrowserMozillaExtensionID(
                "{d634138d-c276-4fc8-924b-40a0ea21d284}"
            )
        )
        let hostName = "com.example.firefox_echo"
        let executable = root.appending(path: "firefox-host.py")
        let script = """
            #!/usr/bin/python3
            import json, struct, sys
            header = sys.stdin.buffer.read(4)
            size = struct.unpack('<I', header)[0]
            sys.stdin.buffer.read(size)
            payload = json.dumps({'arguments': sys.argv[1:]}).encode('utf-8')
            sys.stdout.buffer.write(struct.pack('<I', len(payload)) + payload)
            sys.stdout.buffer.flush()
            """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let manifestURL = root.appending(path: "\(hostName).json")
        let manifest: [String: Any] = [
            "name": hostName,
            "path": executable.path,
            "type": "stdio",
            "allowed_extensions": [extensionID.rawValue],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: manifestURL
        )
        let service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(
                chromeSearchDirectories: [],
                mozillaSearchDirectories: [root]
            )
        )
        let response = expectation(description: "Firefox host response")
        var receivedArguments: [String]?
        var receivedError: Error?

        service.sendMessage(
            ["ping": "pong"],
            applicationIdentifier: hostName,
            extensionIdentity: .mozillaAddons(extensionID)
        ) { value, error in
            receivedArguments =
                (value as? [String: Any])?["arguments"] as? [String]
            receivedError = error
            response.fulfill()
        }
        await fulfillment(of: [response], timeout: 5)

        XCTAssertNil(receivedError)
        XCTAssertEqual(
            receivedArguments,
            [manifestURL.path, extensionID.rawValue]
        )
    }

    func testResolverRequiresAnExactExtensionOrigin() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-native-host-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "host")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let manifestURL = root.appending(path: "com.example.host.json")
        let manifest: [String: Any] = [
            "name": "com.example.host",
            "description": "Crest test host",
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://abcdefghijklmnopabcdefghijklmnop/"
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: manifestURL
        )
        let resolver = BrowserNativeMessagingHostManifestResolver(
            searchDirectories: [root]
        )

        let resolved = try resolver.resolve(
            hostName: "com.example.host",
            extensionID: try XCTUnwrap(
                BrowserChromeExtensionID(
                    "abcdefghijklmnopabcdefghijklmnop"
                ))
        )
        XCTAssertEqual(resolved.executableURL, executable)

        XCTAssertThrowsError(
            try resolver.resolve(
                hostName: "com.example.host",
                extensionID: try XCTUnwrap(
                    BrowserChromeExtensionID(
                        "bcdefghijklmnopabcdefghijklmnopa"
                    ))
            )
        )
    }

    func testResolverRequiresAnExactFirefoxExtensionIDAndInvocation() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-firefox-native-host-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "host")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let hostName = "com.example.firefox_host"
        let extensionID = try XCTUnwrap(
            BrowserMozillaExtensionID(
                "{d634138d-c276-4fc8-924b-40a0ea21d284}"
            )
        )
        let manifestURL = root.appending(path: "\(hostName).json")
        let manifest: [String: Any] = [
            "name": hostName,
            "path": executable.path,
            "type": "stdio",
            "allowed_extensions": [extensionID.rawValue],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: manifestURL
        )
        let resolver = BrowserNativeMessagingHostManifestResolver(
            chromeSearchDirectories: [],
            mozillaSearchDirectories: [root]
        )

        let resolved = try resolver.resolve(
            hostName: hostName,
            extensionIdentity: .mozillaAddons(extensionID)
        )

        XCTAssertEqual(resolved.executableURL, executable)
        XCTAssertEqual(
            resolved.arguments,
            [manifestURL.path, extensionID.rawValue]
        )
        XCTAssertThrowsError(
            try resolver.resolve(
                hostName: hostName,
                extensionIdentity: .mozillaAddons(
                    try XCTUnwrap(
                        BrowserMozillaExtensionID("other@example.com")
                    )
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserNativeMessagingHostError,
                .originNotAllowed
            )
        }
    }

    @MainActor
    private func capabilityResponse(
        from service: BrowserNativeMessagingService,
        message: [String: Any],
        extensionID: BrowserChromeExtensionID,
        authorization: BrowserExtensionNativeMessagingAuthorization
    ) async -> (value: Any?, error: Error?) {
        let reply = expectation(description: "Capability broker response")
        var receivedValue: Any?
        var receivedError: Error?
        service.sendMessage(
            message,
            applicationIdentifier:
                BrowserNativeMessagingService.capabilityBrokerIdentifier,
            extensionIdentity: .chromeWebStore(extensionID),
            authorization: authorization
        ) { value, error in
            receivedValue = value
            receivedError = error
            reply.fulfill()
        }
        await fulfillment(of: [reply], timeout: 1)
        return (receivedValue, receivedError)
    }

    func testResolverSelectsTheOnlyAllowedHostForAnUnnamedChromeRequest()
        throws
    {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-unnamed-native-host-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "host")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let manifest: [String: Any] = [
            "name": "com.example.allowed",
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://\(extensionID.rawValue)/"
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appending(path: "com.example.allowed.json")
        )
        let resolver = BrowserNativeMessagingHostManifestResolver(
            searchDirectories: [root]
        )

        let resolved = try resolver.resolve(
            hostName: "",
            extensionID: extensionID
        )

        XCTAssertEqual(resolved.name, "com.example.allowed")
        XCTAssertEqual(resolved.executableURL, executable)
        XCTAssertEqual(
            resolved.arguments,
            ["chrome-extension://\(extensionID.rawValue)/"]
        )
    }

    func testResolverRejectsAnUnnamedRequestWhenMultipleHostsAreAllowed()
        throws
    {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-ambiguous-native-host-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "host")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        for hostName in ["com.example.first", "com.example.second"] {
            let manifest: [String: Any] = [
                "name": hostName,
                "path": executable.path,
                "type": "stdio",
                "allowed_origins": [
                    "chrome-extension://\(extensionID.rawValue)/"
                ],
            ]
            try JSONSerialization.data(withJSONObject: manifest).write(
                to: root.appending(path: "\(hostName).json")
            )
        }
        let resolver = BrowserNativeMessagingHostManifestResolver(
            searchDirectories: [root]
        )

        XCTAssertThrowsError(
            try resolver.resolve(hostName: "", extensionID: extensionID)
        ) { error in
            XCTAssertEqual(
                error as? BrowserNativeMessagingHostError,
                .unnamedHostUnavailable
            )
        }
    }

    func testResolverIgnoresAnUnnamedManifestWhoseFilenameDoesNotMatchItsName()
        throws
    {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-misnamed-native-host-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "host")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let manifest: [String: Any] = [
            "name": "com.example.declared",
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://\(extensionID.rawValue)/"
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appending(path: "com.example.registered.json")
        )
        let resolver = BrowserNativeMessagingHostManifestResolver(
            searchDirectories: [root]
        )

        XCTAssertThrowsError(
            try resolver.resolve(hostName: "", extensionID: extensionID)
        ) { error in
            XCTAssertEqual(
                error as? BrowserNativeMessagingHostError,
                .unnamedHostUnavailable
            )
        }
    }

    func testResolverPreservesDirectoryPrecedenceForAnUnnamedHost() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-shadowed-native-host-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let first = root.appending(path: "first", directoryHint: .isDirectory)
        let second = root.appending(path: "second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: first,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: second,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "host")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let extensionID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "abcdefghijklmnopabcdefghijklmnop"
            )
        )
        let hostName = "com.example.shadowed"
        let deniedManifest: [String: Any] = [
            "name": hostName,
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://ponmlkjihgfedcbaponmlkjihgfedcba/"
            ],
        ]
        let allowedManifest: [String: Any] = [
            "name": hostName,
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://\(extensionID.rawValue)/"
            ],
        ]
        try JSONSerialization.data(withJSONObject: deniedManifest).write(
            to: first.appending(path: "\(hostName).json")
        )
        try JSONSerialization.data(withJSONObject: allowedManifest).write(
            to: second.appending(path: "\(hostName).json")
        )
        let resolver = BrowserNativeMessagingHostManifestResolver(
            searchDirectories: [first, second]
        )

        XCTAssertThrowsError(
            try resolver.resolve(hostName: "", extensionID: extensionID)
        ) { error in
            XCTAssertEqual(
                error as? BrowserNativeMessagingHostError,
                .unnamedHostUnavailable
            )
        }
    }

    func testResolverSelectsTheOnlyAllowedHostForAnUnnamedFirefoxRequest()
        throws
    {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-unnamed-firefox-host-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "host")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let extensionID = try XCTUnwrap(
            BrowserMozillaExtensionID("native@example.com")
        )
        let hostName = "com.example.firefox_allowed"
        let manifestURL = root.appending(path: "\(hostName).json")
        let manifest: [String: Any] = [
            "name": hostName,
            "path": executable.path,
            "type": "stdio",
            "allowed_extensions": [extensionID.rawValue],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: manifestURL
        )
        let resolver = BrowserNativeMessagingHostManifestResolver(
            chromeSearchDirectories: [],
            mozillaSearchDirectories: [root]
        )

        let resolved = try resolver.resolve(
            hostName: "",
            extensionIdentity: .mozillaAddons(extensionID)
        )

        XCTAssertEqual(resolved.name, hostName)
        XCTAssertEqual(resolved.executableURL, executable)
        XCTAssertEqual(resolved.arguments.count, 2)
        XCTAssertEqual(
            URL(filePath: try XCTUnwrap(resolved.arguments.first))
                .lastPathComponent,
            manifestURL.lastPathComponent
        )
        XCTAssertEqual(resolved.arguments.last, extensionID.rawValue)
    }

    func testResolverRejectsPathTraversalAsAHostName() throws {
        let resolver = BrowserNativeMessagingHostManifestResolver(
            searchDirectories: []
        )
        XCTAssertThrowsError(
            try resolver.resolve(
                hostName: "../host",
                extensionID: try XCTUnwrap(
                    BrowserChromeExtensionID(
                        "abcdefghijklmnopabcdefghijklmnop"
                    ))
            )
        )
    }

    func testResolverOnlyExposesAnExactBuiltInHostToItsExpectedExtension()
        throws
    {
        let executable = URL(filePath: "/bin/echo")
        let expectedID = try XCTUnwrap(
            BrowserChromeExtensionID(
                "pejdijmoenmkgeppbflobdenhhabjlaj"
            )
        )
        let resolver = BrowserNativeMessagingHostManifestResolver(
            searchDirectories: [],
            builtInHosts: [
                BrowserNativeMessagingBuiltInHost(
                    name: "com.apple.passwordmanager",
                    extensionID: expectedID,
                    executableURL: executable
                )
            ]
        )

        XCTAssertEqual(
            try resolver.resolve(
                hostName: "com.apple.passwordmanager",
                extensionID: expectedID
            ).executableURL,
            executable
        )

        XCTAssertThrowsError(
            try resolver.resolve(
                hostName: "com.apple.passwordmanager",
                extensionID: try XCTUnwrap(
                    BrowserChromeExtensionID(
                        "abcdefghijklmnopabcdefghijklmnop"
                    )
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? BrowserNativeMessagingHostError,
                .hostNotFound("com.apple.passwordmanager")
            )
        }
    }

    func testFrameDecoderWaitsForCompleteMessages() throws {
        let message = try BrowserNativeMessagingFrameCodec.encode(
            ["ready": true]
        )
        var decoder = BrowserNativeMessagingFrameDecoder()

        XCTAssertTrue(try decoder.append(message.prefix(3)).isEmpty)
        let values = try decoder.append(message.dropFirst(3))
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(
            (values[0] as? [String: Bool])?["ready"],
            true
        )
    }

    func testFrameDecoderRejectsOversizedHostMessages() throws {
        var frame = Data()
        var size = UInt32(1_048_577).littleEndian
        withUnsafeBytes(of: &size) { frame.append(contentsOf: $0) }
        var decoder = BrowserNativeMessagingFrameDecoder()

        XCTAssertThrowsError(try decoder.append(frame))
    }

    func testFrameDecoderDecodesTwoFramesCoalescedIntoOneChunk() throws {
        let first = try Self.frame("one")
        let second = try Self.frame("two")
        var decoder = BrowserNativeMessagingFrameDecoder()

        let values = try decoder.append(first + second)

        XCTAssertEqual(Self.steps(values), ["one", "two"])
    }

    func testFrameDecoderDecodesOneFramePerChunk() throws {
        var decoder = BrowserNativeMessagingFrameDecoder()

        for step in ["one", "two", "three"] {
            let values = try decoder.append(try Self.frame(step))
            XCTAssertEqual(Self.steps(values), [step])
        }
    }

    func testFrameDecoderResumesWhenALengthHeaderStraddlesChunks() throws {
        var decoder = BrowserNativeMessagingFrameDecoder()
        XCTAssertEqual(
            Self.steps(try decoder.append(try Self.frame("one"))),
            ["one"]
        )
        let straddled = try Self.frame("two")

        XCTAssertTrue(try decoder.append(straddled.prefix(2)).isEmpty)

        XCTAssertEqual(
            Self.steps(try decoder.append(straddled.dropFirst(2))),
            ["two"]
        )
    }

    func testFrameDecoderResumesWhenAPayloadStraddlesChunks() throws {
        var decoder = BrowserNativeMessagingFrameDecoder()
        XCTAssertEqual(
            Self.steps(try decoder.append(try Self.frame("one"))),
            ["one"]
        )
        let straddled = try Self.frame("two")

        XCTAssertTrue(try decoder.append(straddled.prefix(6)).isEmpty)

        XCTAssertEqual(
            Self.steps(try decoder.append(straddled.dropFirst(6))),
            ["two"]
        )
    }

    func testFrameDecoderCarriesAPartialFrameIntoTheFollowingChunk() throws {
        let first = try Self.frame("one")
        let second = try Self.frame("two")
        let third = try Self.frame("three")
        var decoder = BrowserNativeMessagingFrameDecoder()

        XCTAssertEqual(
            Self.steps(try decoder.append(first + second.prefix(6))),
            ["one"]
        )

        XCTAssertEqual(
            Self.steps(try decoder.append(second.dropFirst(6) + third)),
            ["two", "three"]
        )
    }

    func testFrameDecoderStillRejectsOversizedHostMessagesAfterAFrame() throws {
        var decoder = BrowserNativeMessagingFrameDecoder()
        XCTAssertEqual(
            Self.steps(try decoder.append(try Self.frame("one"))),
            ["one"]
        )
        var oversized = Data()
        var size = UInt32(
            BrowserNativeMessagingFrameCodec.maximumHostMessageSize + 1
        ).littleEndian
        withUnsafeBytes(of: &size) { oversized.append(contentsOf: $0) }

        XCTAssertThrowsError(try decoder.append(oversized)) { error in
            XCTAssertEqual(
                error as? BrowserNativeMessagingHostError,
                .messageTooLarge
            )
        }
    }

    @MainActor
    func testConnectionDeliversEveryHostReplyInOrder() async throws {
        try Self.skipUnlessNativeHostsCanLaunch()
        let executable = try makeHostExecutable(Self.echoHostScript)
        let steps = (1...8).map { "message-\($0)" }
        let replies = expectation(description: "Ordered native host replies")
        var received: [String] = []
        var failure: Error?

        let connection = try BrowserNativeMessagingProcessConnection(
            host: BrowserNativeMessagingHostManifest(
                name: "com.example.echo",
                executableURL: executable
            ),
            extensionID: try Self.extensionID(),
            receive: { value in
                let echo =
                    (value as? [String: Any])?["echo"] as? [String: String]
                received.append(echo?["step"] ?? "<unreadable>")
                if received.count == steps.count { replies.fulfill() }
            },
            disconnect: { error in
                guard received.count < steps.count else { return }
                failure = error
                replies.fulfill()
            }
        )
        for step in steps { try connection.send(["step": step]) }
        await fulfillment(of: [replies], timeout: 20)
        connection.disconnect()

        XCTAssertNil(failure)
        XCTAssertEqual(received, steps)
    }

    @MainActor
    func testSendingALargeMessageDoesNotBlockTheMainActor() async throws {
        try Self.skipUnlessNativeHostsCanLaunch()
        let executable = try makeHostExecutable(Self.slowReaderHostScript)
        let message = ["payload": String(repeating: "c", count: 512 * 1_024)]
        let expectedPayloadBytes =
            try BrowserNativeMessagingFrameCodec.encode(message).count - 4
        let reply = expectation(description: "Native host drained stdin")
        var reportedBytes: Int?
        var failure: Error?

        let connection = try BrowserNativeMessagingProcessConnection(
            host: BrowserNativeMessagingHostManifest(
                name: "com.example.slow",
                executableURL: executable
            ),
            extensionID: try Self.extensionID(),
            receive: { value in
                reportedBytes = (value as? [String: Any])?["bytes"] as? Int
                reply.fulfill()
            },
            disconnect: { error in
                guard reportedBytes == nil else { return }
                failure = error
                reply.fulfill()
            }
        )
        let started = ContinuousClock.now
        try connection.send(message)
        let elapsed = ContinuousClock.now - started
        await fulfillment(of: [reply], timeout: 30)
        connection.disconnect()

        XCTAssertNil(failure)
        XCTAssertEqual(reportedBytes, expectedPayloadBytes)
        XCTAssertLessThan(
            elapsed,
            .milliseconds(250),
            "A blocking pipe write must not run on the main actor."
        )
    }

    @MainActor
    func testConnectionTerminatesAHostThatNeverReplies() async throws {
        try Self.skipUnlessNativeHostsCanLaunch()
        let executable = try makeHostExecutable(Self.silentHostScript)
        let teardown = expectation(description: "Connection tore itself down")
        var failure: Error?

        let connection = try BrowserNativeMessagingProcessConnection(
            host: BrowserNativeMessagingHostManifest(
                name: "com.example.silent",
                executableURL: executable
            ),
            extensionID: try Self.extensionID(),
            replyTimeout: .milliseconds(300),
            receive: { _ in },
            disconnect: { error in
                failure = error
                teardown.fulfill()
            }
        )
        try connection.send(["ping": "pong"])
        await fulfillment(of: [teardown], timeout: 5)

        XCTAssertEqual(
            failure as? BrowserNativeMessagingHostError,
            .timedOut
        )
        for _ in 0..<50 where connection.isHostRunning {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(connection.isHostRunning)
    }

    @MainActor
    func testSendingToAHostThatExitedReportsAnErrorInsteadOfRaisingSIGPIPE()
        async throws
    {
        try Self.skipUnlessNativeHostsCanLaunch()
        let executable = try makeHostExecutable(Self.quittingHostScript)
        let teardown = expectation(description: "Broken pipe reported")
        var failure: Error?

        let connection = try BrowserNativeMessagingProcessConnection(
            host: BrowserNativeMessagingHostManifest(
                name: "com.example.quitting",
                executableURL: executable
            ),
            extensionID: try Self.extensionID(),
            receive: { _ in },
            disconnect: { error in
                failure = error
                teardown.fulfill()
            }
        )
        try connection.send(["payload": String(repeating: "c", count: 512 * 1_024)])
        await fulfillment(of: [teardown], timeout: 10)
        connection.disconnect()

        XCTAssertNotNil(failure)
    }

    @MainActor
    func testSendMessageSurfacesATimeoutWhenTheHostNeverReplies() async throws {
        try Self.skipUnlessNativeHostsCanLaunch()
        let hostName = "com.example.silent"
        let extensionID = try Self.extensionID()
        let root = try installHostManifest(
            for: try makeHostExecutable(Self.silentHostScript),
            hostName: hostName,
            extensionID: extensionID
        )
        let service = BrowserNativeMessagingService(
            capability: .available,
            resolver: BrowserNativeMessagingHostManifestResolver(
                searchDirectories: [root]
            ),
            replyTimeout: .milliseconds(300)
        )
        let reply = expectation(description: "Timed out native host reply")
        var received: Any?
        var failure: Error?

        service.sendMessage(
            ["ping": "pong"],
            applicationIdentifier: hostName,
            extensionID: extensionID
        ) { value, error in
            received = value
            failure = error
            reply.fulfill()
        }
        await fulfillment(of: [reply], timeout: 5)

        XCTAssertNil(received)
        XCTAssertEqual(
            failure as? BrowserNativeMessagingHostError,
            .timedOut
        )
    }

    private func installHostManifest(
        for executable: URL,
        hostName: String,
        extensionID: BrowserChromeExtensionID
    ) throws -> URL {
        let root = executable.deletingLastPathComponent()
        let manifest: [String: Any] = [
            "name": hostName,
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://\(extensionID.rawValue)/"
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appending(path: "\(hostName).json")
        )
        return root
    }

    private func makeHostExecutable(_ script: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-native-transport-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "host.py")
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return executable
    }

    private static func skipUnlessNativeHostsCanLaunch() throws {
        guard
            BrowserPlatformExtensionNativeMessagingCapability.currentBuild
                == .available
        else {
            throw XCTSkip("This build cannot launch native hosts.")
        }
    }

    private static func extensionID() throws -> BrowserChromeExtensionID {
        try XCTUnwrap(
            BrowserChromeExtensionID("abcdefghijklmnopabcdefghijklmnop")
        )
    }

    private static func frame(_ step: String) throws -> Data {
        try BrowserNativeMessagingFrameCodec.encode(["step": step])
    }

    private static func steps(_ values: [Any]) -> [String] {
        values.map { ($0 as? [String: String])?["step"] ?? "<unreadable>" }
    }

    private static let echoHostScript = """
        #!/usr/bin/python3
        import json, struct, sys
        while True:
            header = sys.stdin.buffer.read(4)
            if len(header) < 4:
                break
            size = struct.unpack('<I', header)[0]
            message = json.loads(sys.stdin.buffer.read(size))
            payload = json.dumps({'echo': message}).encode('utf-8')
            sys.stdout.buffer.write(struct.pack('<I', len(payload)) + payload)
            sys.stdout.buffer.flush()
        """

    private static let silentHostScript = """
        #!/usr/bin/python3
        import time
        time.sleep(20)
        """

    private static let quittingHostScript = """
        #!/usr/bin/python3
        import time
        time.sleep(0.4)
        """

    // MARK: - Brokered worker WebSocket

    /// Drives the broker's half of the transport against a real WebSocket
    /// server.
    ///
    /// The worker-side facade is only half of this capability, and a stub on
    /// this side would pin nothing that matters: what has to hold is that the
    /// envelope reaches a socket that really speaks the protocol, that binary
    /// survives the base64 round trip JSON forces on it, and that a peer's
    /// close code arrives intact.
    @MainActor
    func testBrokeredWebSocketCarriesTextBinaryAndAPeerCloseCode()
        async throws
    {
        let server = BrokeredWebSocketEchoServer(subprotocol: "codex")
        let port = try server.start()
        defer { server.stop() }
        let log = BrokeredWebSocketEventLog()
        let connection = try brokerConnection(
            contentSecurityPolicy: "connect-src ws://127.0.0.1:\(port)",
            log: log
        )
        defer { connection.stop() }

        try connection.receive([
            "api": "websocket.open",
            "url": "ws://127.0.0.1:\(port)/console",
            "protocols": ["codex"],
        ])

        let opened = try await nextEvent("open", from: log)
        XCTAssertEqual(opened["api"] as? String, "websocket.event")
        XCTAssertEqual(opened["protocol"] as? String, "codex")
        XCTAssertEqual(server.requestedSubprotocols, ["codex"])
        XCTAssertEqual(
            server.requestedOrigin,
            "chrome-extension://abcdefghijklmnopabcdefghijklmnop"
        )

        try connection.receive(["api": "websocket.send", "text": "hello"])
        let echoedText = try await nextEvent("message", from: log)
        XCTAssertEqual(echoedText["text"] as? String, "hello")
        let textAcknowledgement = try await nextEvent("sent", from: log)
        XCTAssertEqual(textAcknowledgement["bytes"] as? Int, 5)

        let payload = Data([0x00, 0x01, 0xfe, 0xff])
        try connection.receive([
            "api": "websocket.send",
            "binaryBase64": payload.base64EncodedString(),
        ])
        let echoedBinary = try await nextEvent("message", from: log)
        XCTAssertNil(echoedBinary["text"])
        XCTAssertEqual(
            Data(
                base64Encoded: (echoedBinary["binaryBase64"] as? String) ?? ""
            ),
            payload
        )
        let binaryAcknowledgement = try await nextEvent("sent", from: log)
        XCTAssertEqual(binaryAcknowledgement["bytes"] as? Int, 4)

        server.closeConnections(code: 4001)

        let closed = try await nextEvent("close", from: log)
        XCTAssertEqual(closed["code"] as? Int, 4001)
        XCTAssertEqual(closed["wasClean"] as? Bool, true)
        XCTAssertNil(log.messages.first { $0["kind"] as? String == "error" })
    }

    /// A socket the worker closes itself reports the code it asked for, and
    /// the peer sees the connection go away.
    @MainActor
    func testBrokeredWebSocketReportsAWorkerInitiatedClose() async throws {
        let server = BrokeredWebSocketEchoServer(subprotocol: nil)
        let port = try server.start()
        defer { server.stop() }
        let log = BrokeredWebSocketEventLog()
        let connection = try brokerConnection(
            contentSecurityPolicy: nil,
            log: log
        )
        defer { connection.stop() }

        try connection.receive([
            "api": "websocket.open",
            "url": "ws://127.0.0.1:\(port)/console",
        ])
        let opened = try await nextEvent("open", from: log)
        XCTAssertEqual(opened["protocol"] as? String, "")

        try connection.receive([
            "api": "websocket.close",
            "code": 4002,
            "reason": "done",
        ])

        let closed = try await nextEvent("close", from: log)
        XCTAssertEqual(closed["code"] as? Int, 4002)
        XCTAssertEqual(closed["reason"] as? String, "done")
        XCTAssertEqual(closed["wasClean"] as? Bool, true)
    }

    /// WebKit cannot apply the extension's own `connect-src` to a socket
    /// opened outside its process, so the broker does it — and a refusal drops
    /// the port, which the worker-side facade reports as a failed handshake.
    @MainActor
    func testBrokeredWebSocketRefusesADestinationTheManifestDenies() throws {
        let log = BrokeredWebSocketEventLog()
        let connection = try brokerConnection(
            contentSecurityPolicy:
                "script-src 'self'; connect-src wss://api.example.com",
            log: log
        )
        defer { connection.stop() }

        XCTAssertThrowsError(
            try connection.receive([
                "api": "websocket.open",
                "url": "ws://127.0.0.1:1455/console",
            ])
        ) { error in
            XCTAssertEqual(
                error as? BrowserExtensionCapabilityBrokerError,
                .permissionDenied("connect-src")
            )
        }
        XCTAssertTrue(log.messages.isEmpty)

        XCTAssertThrowsError(
            try connection.receive([
                "api": "websocket.open",
                "url": "https://api.example.com/",
            ])
        ) { error in
            XCTAssertEqual(
                error as? BrowserExtensionCapabilityBrokerError,
                .invalidRequest
            )
        }
    }

    /// A WebSocket asks for no extension permission — Chrome requires none —
    /// but it still requires the broker grant every capability port has.
    @MainActor
    func testBrokeredWebSocketRequiresTheInternalBrokerGrant() throws {
        var published: [[String: Any]] = []
        let connection = BrowserExtensionCapabilityBrokerConnection(
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: ["idle", "notifications"],
                clientID: BrowserExtensionServiceClientID("extension.space"),
                allowsInternalCapabilityBroker: false
            ),
            notificationService: nil,
            idleStateProvider: { _ in .active },
            webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry(),
            publish: { published.append($0) }
        )
        defer { connection.stop() }

        XCTAssertThrowsError(
            try connection.receive([
                "api": "websocket.open",
                "url": "wss://api.example.com/",
            ])
        ) { error in
            XCTAssertEqual(
                error as? BrowserExtensionCapabilityBrokerError,
                .permissionDenied("internalCapabilityBroker")
            )
        }
        XCTAssertTrue(published.isEmpty)
    }

    /// Waits for one published socket event, failing the test if it never
    /// arrives rather than hanging until the suite's own timeout.
    @MainActor
    private func nextEvent(
        _ kind: String,
        from log: BrokeredWebSocketEventLog,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [String: Any] {
        let event = await log.consume(kind: kind)
        return try XCTUnwrap(
            event,
            "No \(kind) event arrived.",
            file: file,
            line: line
        )
    }

    @MainActor
    private func brokerConnection(
        contentSecurityPolicy: String?,
        log: BrokeredWebSocketEventLog
    ) throws -> BrowserExtensionCapabilityBrokerConnection {
        let clientID = try XCTUnwrap(
            BrowserExtensionServiceClientID(
                "abcdefghijklmnopabcdefghijklmnop.space."
                    + UUID().uuidString.lowercased()
            )
        )
        return BrowserExtensionCapabilityBrokerConnection(
            authorization: BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: [],
                clientID: clientID,
                allowsInternalCapabilityBroker: true,
                contentSecurityPolicy: contentSecurityPolicy
            ),
            notificationService: nil,
            idleStateProvider: { _ in .active },
            webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry(),
            publish: { log.record($0) }
        )
    }

    private static let slowReaderHostScript = """
        #!/usr/bin/python3
        import json, struct, sys, time
        time.sleep(1.5)
        header = sys.stdin.buffer.read(4)
        size = struct.unpack('<I', header)[0]
        payload = sys.stdin.buffer.read(size)
        reply = json.dumps({'bytes': len(payload)}).encode('utf-8')
        sys.stdout.buffer.write(struct.pack('<I', len(reply)) + reply)
        sys.stdout.buffer.flush()
        """
}

/// Collects what the broker publishes back to a capability port.
@MainActor
private final class BrokeredWebSocketEventLog {
    private(set) var messages: [[String: Any]] = []
    private var consumed: Set<Int> = []

    func record(_ message: [String: Any]) {
        messages.append(message)
    }

    /// Waits for the next event of `kind` that no earlier call has taken.
    ///
    /// Events arrive from a live socket, so a message echo and its `sent`
    /// acknowledgement can land in either order: a single cursor would make
    /// the test depend on which won.
    func consume(kind: String) async -> [String: Any]? {
        for _ in 0..<1000 {
            if let index = messages.indices.first(
                where: {
                    !consumed.contains($0)
                        && messages[$0]["kind"] as? String == kind
                }
            ) {
                consumed.insert(index)
                return messages[index]
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }
}

/// A WebSocket server the brokered-socket tests connect to.
///
/// Network.framework rather than a stub: what these tests exist to prove is
/// that `URLSessionWebSocketTask` really carries the extension's frames, and a
/// fake transport would prove nothing about that.
private final class BrokeredWebSocketEchoServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "crest.tests.websocket-echo")
    private let lock = NSLock()
    private let negotiatedSubprotocol: String?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var observedSubprotocols: [String] = []
    private var observedOrigin: String?

    init(subprotocol: String?) {
        negotiatedSubprotocol = subprotocol
    }

    var requestedSubprotocols: [String] {
        lock.withLock { observedSubprotocols }
    }

    var requestedOrigin: String? {
        lock.withLock { observedOrigin }
    }

    func start() throws -> UInt16 {
        let parameters = NWParameters.tcp
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        options.setClientRequestHandler(queue) {
            [weak self] subprotocols, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }
            self?.lock.withLock {
                self?.observedSubprotocols = subprotocols
                self?.observedOrigin = origin?.value
            }
            return NWProtocolWebSocket.Response(
                status: .accept,
                subprotocol: self?.negotiatedSubprotocol
            )
        }
        parameters.defaultProtocolStack.applicationProtocols.insert(
            options,
            at: 0
        )
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            lock.withLock { connections.append(connection) }
            connection.start(queue: queue)
            echo(on: connection)
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 10) == .success,
            let port = listener.port?.rawValue
        else {
            throw BrokeredWebSocketEchoServerError.unavailable
        }
        return port
    }

    func closeConnections(code: UInt16) {
        let open = lock.withLock { connections }
        for connection in open {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
            metadata.closeCode = .applicationCode(code)
            connection.send(
                content: nil,
                contentContext: NWConnection.ContentContext(
                    identifier: "close",
                    metadata: [metadata]
                ),
                isComplete: true,
                completion: .contentProcessed { _ in }
            )
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        let open = lock.withLock {
            let current = connections
            connections = []
            return current
        }
        for connection in open { connection.cancel() }
    }

    private func echo(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self, error == nil else { return }
            guard
                let metadata = context?.protocolMetadata(
                    definition: NWProtocolWebSocket.definition
                ) as? NWProtocolWebSocket.Metadata
            else {
                return
            }
            if metadata.opcode == .text || metadata.opcode == .binary {
                connection.send(
                    content: content,
                    contentContext: NWConnection.ContentContext(
                        identifier: "echo",
                        metadata: [
                            NWProtocolWebSocket.Metadata(
                                opcode: metadata.opcode
                            )
                        ]
                    ),
                    isComplete: true,
                    completion: .contentProcessed { _ in }
                )
            }
            guard metadata.opcode != .close else { return }
            echo(on: connection)
        }
    }
}

private enum BrokeredWebSocketEchoServerError: Error {
    case unavailable
}
