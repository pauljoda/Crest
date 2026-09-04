import WebKit
import XCTest

@testable import Crest

/// The `chrome.debugger` capability broker end of the namespace: what a wire
/// request may name, what it is answered with, and in whose words.
@MainActor
final class BrowserExtensionDebuggerCapabilityBrokerTests: XCTestCase {
    func testAttachRequiresTheBrokerGrantAndThenTheUsersConsent() async throws {
        try await withHarness { harness in
            harness.authorize([])
            await self.assertFails(try await harness.attach())
            harness.authorize(["debugger"])

            harness.consent.answer = false
            await self.assertFails(try await harness.attach(), "Cannot attach to this target.")
            XCTAssertEqual(harness.consent.count, 1)
            XCTAssertEqual(harness.decision, .block)

            // A refusal is remembered, so the extension cannot re-prompt.
            await self.assertFails(try await harness.attach(), "Cannot attach to this target.")
            XCTAssertEqual(harness.consent.count, 1)

            harness.decision = .ask
            harness.consent.answer = true
            let reply = try await harness.attach()
            XCTAssertFalse((reply["sessionToken"] as? String ?? "").isEmpty)
            XCTAssertEqual(harness.consent.count, 2)
            XCTAssertEqual(harness.decision, .allow)
            XCTAssertEqual(harness.store.sessions.count, 1)
            XCTAssertEqual(harness.store.sessions.first?.target.tabID, harness.webTab.id)

            // An allowed decision attaches without asking again.
            _ = try await harness.detach(token: try XCTUnwrap(reply["sessionToken"] as? String))
            _ = try await harness.attach()
            XCTAssertEqual(harness.consent.count, 2)
        }
    }

    func testAttachRejectsUnknownTabsBadVersionsRestrictedPagesAndSecondSessions() async throws {
        try await withHarness { harness in
            harness.authorize(["debugger"])
            harness.decision = .allow

            await self.assertFails(
                try await harness.attach(tabIndex: 99, tabID: 41), "No tab with given id 41.")
            await self.assertFails(
                try await harness.attach(version: "0.9"), "Requested protocol version is not supported: 0.9.")
            // A tab index that exists but whose URL no longer matches what the
            // caller resolved is not the tab it named.
            await self.assertFails(
                try await harness.attach(url: "https://elsewhere.test/"), "No tab with given id 7.")
            // Crest's Start Page has no document and no host to match.
            await self.assertFails(
                try await harness.attach(tabIndex: harness.startTab.index, sendsURL: false),
                "Cannot attach to this target.")

            _ = try await harness.attach()
            await self.assertFails(
                try await harness.attach(), "Another debugger is already attached to the tab with id: 7.")
        }
    }

    func testCommandsAddressTheBoundTokenAndUnimplementedMethodsUseTheProtocolText() async throws {
        try await withHarness { harness in
            harness.authorize(["debugger"])
            harness.decision = .allow
            let attached = try await harness.attach()
            let token = try XCTUnwrap(attached["sessionToken"] as? String)

            let result = try await harness.sendCommand(
                token: token, method: "Runtime.evaluate", params: ["expression": "document.title"])
            XCTAssertEqual(
                ((result["result"] as? [String: Any])?["result"] as? [String: Any])?["value"] as? String,
                "Debugger target")

            await self.assertFails(
                try await harness.sendCommand(token: token, method: "Input.dispatchKeyEvent"),
                "'Input.dispatchKeyEvent' wasn't found")
            await self.assertFails(
                try await harness.sendCommand(token: "not-a-token", method: "Runtime.evaluate"),
                "Debugger is not attached to the tab with id: 7.")
            // The binding is the tab, not the index: a token minted for this
            // session keeps working while another request naming the same
            // index is refused.
            await self.assertFails(
                try await harness.attach(), "Another debugger is already attached to the tab with id: 7.")
            let stillBound = try await harness.sendCommand(
                token: token, method: "Runtime.evaluate", params: ["expression": "1"])
            XCTAssertNotNil(stillBound["result"])
        }
    }

    func testDetachIsSilentAndCancellationReportsCanceledByUser() async throws {
        try await withHarness { harness in
            harness.authorize(["debugger"])
            harness.decision = .allow
            var attached = try await harness.attach()
            var token = try XCTUnwrap(attached["sessionToken"] as? String)

            var published: [[String: Any]] = []
            let target = BrowserExtensionDebuggerTarget(spaceID: harness.space.id, tabID: harness.webTab.id)
            _ = try await harness.detach(token: token)
            XCTAssertTrue(harness.store.sessions.isEmpty)
            XCTAssertNil(
                harness.pool.debuggerEventMessage(.init(target: target, kind: .detached(.canceledByUser))))
            XCTAssertTrue(published.isEmpty)
            // Detaching is idempotent from the caller's side and reports the
            // same thing a never-attached tab does.
            await self.assertFails(
                try await harness.detach(token: token), "Debugger is not attached to the tab with id: 7.")

            attached = try await harness.attach()
            token = try XCTUnwrap(attached["sessionToken"] as? String)
            harness.store.cancel(target: target)
            let message = try XCTUnwrap(
                harness.pool.debuggerEventMessage(.init(target: target, kind: .detached(.canceledByUser))))
            published.append(message)
            XCTAssertEqual(message["api"] as? String, "debugger.event")
            XCTAssertEqual(message["kind"] as? String, "detach")
            XCTAssertEqual(message["reason"] as? String, "canceled_by_user")
            XCTAssertEqual(message["sessionToken"] as? String, token)
            XCTAssertTrue(harness.store.sessions.isEmpty)
        }
    }

    func testGetTargetsListsTheSpacesTabsAndFlagsTheAttachedOne() async throws {
        try await withHarness { harness in
            harness.authorize(["debugger"])
            // Without the user's grant there is nothing this extension may
            // debug, so the list is empty of attachments rather than refused.
            let ungranted = try await harness.getTargets()
            XCTAssertFalse(ungranted.isEmpty)
            XCTAssertTrue(ungranted.allSatisfy { $0["attached"] as? Bool == false })

            harness.decision = .allow
            _ = try await harness.attach()
            let targets = try await harness.getTargets()
            XCTAssertEqual(targets.count, harness.liveTabCount)
            let attached = targets.filter { $0["attached"] as? Bool == true }
            XCTAssertEqual(attached.count, 1)
            XCTAssertEqual(attached.first?["tabIndex"] as? Int, harness.webTab.index)
            XCTAssertEqual(attached.first?["url"] as? String, harness.webTab.url?.absoluteString)
            XCTAssertEqual(
                attached.first?["id"] as? String,
                "crest-tab-\(harness.webTab.id.rawValue.uuidString.lowercased())")
            // The Start Page is a tab and is listed; it simply carries no URL.
            XCTAssertTrue(targets.contains { $0["tabIndex"] as? Int == harness.startTab.index })
            XCTAssertNil(targets.first { $0["tabIndex"] as? Int == harness.startTab.index }?["url"])
        }
    }

    func testTheEventWatchRequiresTheDeclaredCapabilityAndItsOwnPort() throws {
        let client = try XCTUnwrap(BrowserExtensionServiceClientID("debugger-watch"))
        let store = BrowserExtensionDebuggerSessionStore(
            authorizeClient: { _ in true }, resolveTarget: { _ in .closed })
        defer { store.shutdown() }
        store.register(client: client, spaceID: SpaceID(), displayName: "Probe")
        let ungranted = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(grantedPermissions: [], clientID: client),
            notificationService: nil, idleStateProvider: { _ in .active }, webpageMenuRegistry: .init(),
            debuggerService: store, debuggerEventMessage: { _ in nil }, publish: { _ in })
        defer { ungranted.stop() }
        XCTAssertThrowsError(try ungranted.receive(["api": "debugger.watch"]))

        let granted = BrowserExtensionCapabilityBrokerConnection(
            authorization: .init(grantedPermissions: ["debugger", "idle"], clientID: client),
            notificationService: nil, idleStateProvider: { _ in .active }, webpageMenuRegistry: .init(),
            debuggerService: store, debuggerEventMessage: { _ in nil }, publish: { _ in })
        defer { granted.stop() }
        try granted.receive(["api": "debugger.watch"])
        // Re-subscribing on the same port is how the runtime recovers a
        // reconnect; sharing it with another capability is not.
        try granted.receive(["api": "debugger.watch"])
        XCTAssertThrowsError(try granted.receive(["api": "idle.watch", "detectionIntervalInSeconds": 60]))
    }

    // MARK: - Harness

    private func assertFails(
        _ expression: @autoclosure () async throws -> [String: Any], _ message: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected the broker to refuse this request.", file: file, line: line)
        } catch {
            guard let message else { return }
            XCTAssertEqual(error.localizedDescription, message, file: file, line: line)
        }
    }

    private func withHarness(_ operation: (DebuggerBrokerHarness) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-debugger-broker-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = try await DebuggerBrokerHarness(root: root)
        defer { harness.tearDown() }
        try await operation(harness)
    }
}

private enum DebuggerBrokerHarnessError: Error {
    case setUpFailed(String)
}

@MainActor
private final class DebuggerConsentRecorder {
    var answer = true
    private(set) var count = 0

    func respond() -> Bool {
        count += 1
        return answer
    }
}

@MainActor
private final class DebuggerBrokerPageProvider: BrowserExtensionPageProviding {
    var webViews: [TabID: WKWebView] = [:]

    func extensionWebView(for tabID: TabID, in spaceID: SpaceID) -> WKWebView? { webViews[tabID] }
    func prepareExtensionSelection(session: BrowserSession) {}
    func select(session: BrowserSession) {}
    func extensionReaderModeState(for tabID: TabID, in spaceID: SpaceID) -> BrowserReaderModeState {
        .unavailable
    }
    func setExtensionReaderModeActive(_ isActive: Bool, for tabID: TabID, in spaceID: SpaceID) async throws {}
    func extensionWindowGeometry(in spaceID: SpaceID) -> BrowserExtensionWindowGeometry { .unavailable }
}

/// A loaded extension holding the `debugger` permission, a live inspectable
/// page, and the wire helpers to address the broker the way the compatibility
/// runtime does.
///
/// Nothing here asserts. `XCTUnwrap` reports to whichever test case XCTest
/// believes is running, and a fixture assembled across actor hops is not a
/// reliable place to decide that, so set-up failures are plain Swift errors.
@MainActor
private final class DebuggerBrokerHarness {
    let pool: BrowserExtensionControllerPool
    let browser: BrowserStore
    let store: BrowserExtensionDebuggerSessionStore
    let consent = DebuggerConsentRecorder()
    let space: BrowserSpace
    let context: WKWebExtensionContext
    let extensionID: String
    let webTab: BrowserExtensionTabState
    let startTab: BrowserExtensionTabState
    let liveTabCount: Int

    private let pages = DebuggerBrokerPageProvider()
    private let spaceAccess = BrowserSpaceAccessController()
    private let page: WKWebView

    var decision: BrowserExtensionAccessDecision {
        get { pool.permissionDecision(for: "debugger", extensionID: extensionID, in: space.id) }
        set { pool.setPermissionDecision(newValue, for: "debugger", extensionID: extensionID, in: space.id) }
    }

    init(root: URL) async throws {
        pool = BrowserExtensionControllerPool(packageStore: BrowserExtensionPackageStore(rootURL: root))
        browser = BrowserStore.preview()
        guard let space = browser.session.selectedSpace else {
            throw DebuggerBrokerHarnessError.setUpFailed("The preview session has no selected Space.")
        }
        self.space = space
        let consent = consent
        store = BrowserExtensionDebuggerInstallation.install(
            pool: pool, browser: browser, spaceAccess: spaceAccess, prompt: { _ in consent.respond() })
        pool.connect(browser: browser, pageProvider: pages)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/DebuggerAgentProbeExtension", directoryHint: .isDirectory)
        let installed = try await pool.loadUnpackedExtension(from: fixture, in: space)
        extensionID = installed.id
        guard let context = pool.loadedContext(extensionID: installed.id, in: space.id) else {
            throw DebuggerBrokerHarnessError.setUpFailed("The probe extension did not load.")
        }
        self.context = context
        pool.setHostDecision(.allow, for: "<all_urls>", extensionID: installed.id, in: space.id)

        guard let state = pool.tabWindowCoordinator.currentState?.space(space.id),
            let webTab = state.tabs.first(where: { $0.url != nil }),
            let startTab = state.tabs.first(where: { $0.url == nil })
        else {
            throw DebuggerBrokerHarnessError.setUpFailed("The preview Space has no web tab and Start Page.")
        }
        liveTabCount = state.tabs.count
        self.webTab = webTab
        self.startTab = startTab

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences)
        page = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        page.isInspectable = true
        page.loadHTMLString("<!doctype html><title>Debugger target</title>", baseURL: nil)
        pages.webViews[webTab.id] = page
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (try? await page.evaluateJavaScript("document.title")) as? String != "Debugger target" {
            guard ContinuousClock.now < deadline else {
                throw DebuggerBrokerHarnessError.setUpFailed("The target page never finished loading.")
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    func tearDown() {
        store.shutdown()
        pool.permissionController.browserManagedPermissionsDidChange = nil
        spaceAccess.accessDidChange = nil
    }

    func authorize(_ permissions: Set<String>) {
        pool.tabWindowCoordinator.registerCapabilityBrokerAuthorization(
            .init(
                grantedPermissions: permissions,
                clientID: .scoped(extensionID: extensionID, spaceID: space.id),
                allowsInternalCapabilityBroker: true),
            for: context
        )
    }

    func attach(
        tabIndex: Int? = nil, url: String? = nil, sendsURL: Bool = true, tabID: Int = 7,
        version: String = "1.3"
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "api": "debugger.attach", "tabIndex": tabIndex ?? webTab.index, "tabId": tabID,
            "requiredVersion": version,
        ]
        if sendsURL, let resolved = url ?? webTab.url?.absoluteString { payload["url"] = resolved }
        return try await send(payload)
    }

    func detach(token: String) async throws -> [String: Any] {
        try await send(["api": "debugger.detach", "sessionToken": token, "tabId": 7])
    }

    func sendCommand(token: String, method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        try await send([
            "api": "debugger.sendCommand", "sessionToken": token, "method": method, "params": params,
            "tabId": 7,
        ])
    }

    func getTargets() async throws -> [[String: Any]] {
        try (await send(["api": "debugger.getTargets"])["targets"] as? [[String: Any]]) ?? []
    }

    private func send(_ payload: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Reply, any Error>) in
            pool.tabWindowCoordinator.webExtensionController(
                pool.controller(for: space), sendMessage: payload,
                toApplicationWithIdentifier: BrowserExtensionNativeMessagingApplication
                    .capabilityBrokerIdentifier,
                for: context
            ) { value, failure in
                if let failure {
                    continuation.resume(throwing: failure)
                } else {
                    continuation.resume(returning: Reply(value: value as? [String: Any] ?? [:]))
                }
            }
        }.value
    }

    /// The broker answers on the main actor it was called from; the box only
    /// carries the reply across the continuation's `Sendable` boundary.
    private struct Reply: @unchecked Sendable {
        let value: [String: Any]
    }
}
