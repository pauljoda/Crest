import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionDebuggerSessionStoreTests: XCTestCase {
    func testUnregisteredAndCrossSpaceClientsCannotResolveATarget() async throws {
        try await withFixture { fixture, store in
            let unregistered = BrowserExtensionServiceClientID.scoped(extensionID: "unknown", spaceID: fixture.space)
            for (client, target) in [
                (unregistered, fixture.target),
                (fixture.client, BrowserExtensionDebuggerTarget(spaceID: SpaceID(), tabID: TabID())),
            ] {
                do {
                    try await store.attach(to: target, for: client, requiredVersion: "1.3")
                    XCTFail("An unowned target must not be inspected.")
                } catch BrowserExtensionDebuggerError.accessDenied {}
            }
            XCTAssertEqual(fixture.resolutionCount, 0)
            XCTAssertTrue(store.sessions.isEmpty)
        }
    }

    func testAttachedOwnerCanEvaluateButAnotherClientCannotExecuteOrDetach() async throws {
        try await withFixture { fixture, store in
            try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
            XCTAssertEqual(store.sessions.count, 1)
            XCTAssertEqual(store.sessions.first?.phase, .attached)
            let response = try await self.evaluate("6 * 7", store: store, fixture: fixture)
            XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? Int, 42)
            do {
                _ = try await store.sendCommand(
                    .init(method: "Runtime.evaluate", parameters: Data("{}".utf8)),
                    to: fixture.target, for: fixture.otherClient)
                XCTFail("Another client must not use the owner's connection.")
            } catch BrowserExtensionDebuggerError.notAttached {}
            XCTAssertThrowsError(try store.detach(from: fixture.target, for: fixture.otherClient))
            try store.detach(from: fixture.target, for: fixture.client)
            XCTAssertTrue(store.sessions.isEmpty)
        }
    }

    func testCompetingAttachmentDoesNotStealTheOwnersInspector() async throws {
        try await withFixture { fixture, store in
            try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
            do {
                try await store.attach(to: fixture.target, for: fixture.otherClient, requiredVersion: "1.3")
                XCTFail("A second client must not take over the existing Inspector.")
            } catch BrowserExtensionDebuggerError.alreadyAttached {}
            let response = try await self.evaluate("40 + 2", store: store, fixture: fixture)
            XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? Int, 42)
        }
    }

    func testRestrictedOrReplacedPageImmediatelyEndsTheSession() async throws {
        try await withFixture { fixture, store in
            try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
            fixture.isRestricted = true
            do {
                _ = try await self.evaluate(
                    "globalThis.crestUnauthorizedEvaluation = true", store: store, fixture: fixture)
                XCTFail("A newly restricted Space must stop commands before explicit reconciliation.")
            } catch BrowserExtensionDebuggerError.accessDenied {}
            XCTAssertTrue(store.sessions.isEmpty)
            let value = try await fixture.page.evaluateJavaScript("typeof crestUnauthorizedEvaluation")
            XCTAssertEqual(value as? String, "undefined")
            fixture.isRestricted = false
            try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
            fixture.page = try await self.page()
            store.reconcileTargets()
            XCTAssertTrue(store.sessions.isEmpty, "Replacing a WKWebView must not transfer debugger authority.")
        }
    }

    func testUnregisterDuringAttachmentCannotCloseAReplacementSession() async throws {
        try await withFixture { fixture, store in
            let first = Task { try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3") }
            try await self.waitUntil { !store.sessions.isEmpty }
            store.unregister(client: fixture.client)
            try await store.attach(to: fixture.target, for: fixture.otherClient, requiredVersion: "1.3")
            _ = await first.result
            XCTAssertEqual(store.sessions.first?.clientID, fixture.otherClient)
            let command = BrowserExtensionDebuggerCommand(
                method: "Runtime.evaluate",
                parameters: Data(#"{"expression":"6 * 7"}"#.utf8))
            let bytes = try await store.sendCommand(command, to: fixture.target, for: fixture.otherClient)
            let response = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? Int, 42)
        }
    }

    func testUserCancellationRejectsAnInFlightPromiseWithoutWaitingForPageCode() async throws {
        try await withFixture { fixture, store in
            try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
            let stopped = self.expectation(description: "Pending command rejected on detach")
            let request = Task { @MainActor in
                do {
                    let command = BrowserExtensionDebuggerCommand(
                        method: "Runtime.evaluate",
                        parameters: Data(
                            #"{"expression":"globalThis.crestPendingStarted = true; new Promise(() => {})","awaitPromise":true}"#
                                .utf8))
                    _ = try await store.sendCommand(command, to: fixture.target, for: fixture.client)
                    XCTFail("A detached command must not report success.")
                } catch {
                    XCTAssertEqual(error as? BrowserExtensionDebuggerError, .detachedWhileHandling)
                }
                stopped.fulfill()
            }
            try await self.waitUntil {
                (try? await fixture.page.evaluateJavaScript("globalThis.crestPendingStarted === true")) as? Bool == true
            }
            store.cancel(target: fixture.target)
            await self.fulfillment(of: [stopped], timeout: 5)
            request.cancel()
            XCTAssertTrue(store.sessions.isEmpty)
        }
    }

    func testUnsupportedProtocolVersionDoesNotConnectToThePage() async throws {
        try await withFixture { fixture, store in
            for version in ["", "1", "1.4", "2.0", "01.3", "1.3 "] {
                do {
                    try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: version)
                    XCTFail("Unsupported versions must not attach.")
                } catch {
                    XCTAssertEqual(error as? BrowserExtensionDebuggerError, .unsupportedVersion(version))
                }
            }
            XCTAssertEqual(fixture.resolutionCount, 0)
            XCTAssertTrue(store.sessions.isEmpty)
        }
    }

    func testExistingUserInspectorIsNotClosedByAFailedExtensionAttachment() async throws {
        try await withFixture { fixture, store in
            let userInspector = BrowserWebInspectorProtocolConnection(webView: fixture.page)
            try await userInspector.connect()
            defer { userInspector.disconnect() }
            do {
                try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
                XCTFail("An extension must not take over the user's existing Inspector.")
            } catch {
                XCTAssertEqual(error as? BrowserExtensionDebuggerError, .alreadyAttached)
            }
            XCTAssertTrue(store.sessions.isEmpty)
            XCTAssertTrue(userInspector.isConnected)
            let response = try await userInspector.sendCommand("Runtime.evaluate", parameters: ["expression": "6 * 7"])
            XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? Int, 42)
        }
    }

    func testTargetClosureFinishesPendingCommandsAndReportsItsReasonOnce() async throws {
        try await withFixture { fixture, store in
            let recorder = EventRecorder()
            let stream = store.events(for: fixture.client)
            let events = Task { for await event in stream { recorder.values.append(event) } }
            defer { events.cancel() }
            try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
            let stopped = self.expectation(description: "Closed target rejects pending command")
            let task = Task {
                do {
                    _ = try await store.sendCommand(
                        .init(
                            method: "Runtime.evaluate",
                            parameters: Data(
                                #"{"expression":"globalThis.crestPendingStarted = true; new Promise(() => {})","awaitPromise":true}"#
                                    .utf8)),
                        to: fixture.target, for: fixture.client)
                    XCTFail("Closing a target must stop its pending request.")
                } catch {
                    XCTAssertEqual(error as? BrowserExtensionDebuggerError, .detachedWhileHandling)
                }
                stopped.fulfill()
            }
            defer { task.cancel() }
            try await self.waitUntil {
                (try? await fixture.page.evaluateJavaScript("crestPendingStarted === true")) as? Bool == true
            }
            fixture.isClosed = true
            store.reconcileTargets()
            store.reconcileTargets()
            await self.fulfillment(of: [stopped], timeout: 5)
            store.unregister(client: fixture.client)
            await events.value
            XCTAssertEqual(recorder.values, [.init(target: fixture.target, kind: .detached(.targetClosed))])
            XCTAssertTrue(store.sessions.isEmpty)
        }
    }

    func testProtocolAndUserDetachEventsOnlyReachTheOwner() async throws {
        try await withFixture { fixture, store in
            let owner = EventRecorder()
            let other = EventRecorder()
            let ownerStream = store.events(for: fixture.client)
            let otherStream = store.events(for: fixture.otherClient)
            let ownerTask = Task { for await event in ownerStream { owner.values.append(event) } }
            let otherTask = Task { for await event in otherStream { other.values.append(event) } }
            defer {
                ownerTask.cancel()
                otherTask.cancel()
            }

            try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
            _ = try await store.sendCommand(
                .init(method: "Runtime.enable", parameters: Data("{}".utf8)),
                to: fixture.target, for: fixture.client)
            try await self.waitUntil { !owner.values.isEmpty }
            XCTAssertTrue(
                owner.values.contains {
                    if case .protocolMessage(let method, _) = $0.kind {
                        return method == "Runtime.executionContextCreated"
                    }
                    return false
                })
            try store.detach(from: fixture.target, for: fixture.client)
            try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
            store.cancel(target: fixture.target)
            store.unregister(client: fixture.client)
            store.unregister(client: fixture.otherClient)
            await ownerTask.value
            await otherTask.value
            XCTAssertTrue(other.values.isEmpty)
            XCTAssertTrue(owner.values.allSatisfy { $0.target == fixture.target })
            XCTAssertEqual(owner.values.filter { $0.kind == .detached(.canceledByUser) }.count, 1)
            XCTAssertEqual(
                owner.values.filter {
                    if case .detached = $0.kind { return true }
                    return false
                }.count, 1, "Explicit API detach must not emit an additional event.")
        }
    }

    func testAResultCompletedAfterAccessRevocationIsNotReturned() async throws {
        try await withFixture { fixture, store in
            try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
            let stopped = self.expectation(description: "Revoked result rejected")
            let task = Task {
                do {
                    _ = try await store.sendCommand(
                        .init(
                            method: "Runtime.evaluate",
                            parameters: Data(
                                #"{"expression":"new Promise(resolve => globalThis.crestResolve = resolve)","awaitPromise":true,"returnByValue":true}"#
                                    .utf8)),
                        to: fixture.target, for: fixture.client)
                    XCTFail("A late result must not cross the revoked access boundary.")
                } catch {
                    XCTAssertEqual(error as? BrowserExtensionDebuggerError, .detachedWhileHandling)
                }
                stopped.fulfill()
            }
            defer { task.cancel() }
            try await self.waitUntil {
                (try? await fixture.page.evaluateJavaScript("typeof crestResolve")) as? String == "function"
            }
            fixture.isRestricted = true
            _ = try await fixture.page.evaluateJavaScript("crestResolve('not for the extension')")
            await self.fulfillment(of: [stopped], timeout: 5)
            XCTAssertTrue(store.sessions.isEmpty)
        }
    }

    func testCallerCancellationDoesNotCancelTheOwnersOtherCommands() async throws {
        try await withFixture { fixture, store in
            try await store.attach(to: fixture.target, for: fixture.client, requiredVersion: "1.3")
            let stopped = self.expectation(description: "Caller cancellation acknowledged")
            let task = Task {
                do {
                    _ = try await store.sendCommand(
                        .init(
                            method: "Runtime.evaluate",
                            parameters: Data(
                                #"{"expression":"globalThis.crestPendingStarted = true; new Promise(() => {})","awaitPromise":true}"#
                                    .utf8)),
                        to: fixture.target, for: fixture.client)
                    XCTFail("A cancelled request must not succeed.")
                } catch {
                    XCTAssertTrue(error is CancellationError)
                }
                stopped.fulfill()
            }
            try await self.waitUntil {
                (try? await fixture.page.evaluateJavaScript("crestPendingStarted === true")) as? Bool == true
            }
            task.cancel()
            await self.fulfillment(of: [stopped], timeout: 5)
            XCTAssertEqual(store.sessions.count, 1)
            let response = try await self.evaluate("6 * 7", store: store, fixture: fixture)
            XCTAssertEqual((response["result"] as? [String: Any])?["value"] as? Int, 42)
        }
    }

    private func evaluate(_ expression: String, store: BrowserExtensionDebuggerSessionStore, fixture: Fixture)
        async throws -> [String: Any]
    {
        let command = BrowserExtensionDebuggerCommand(
            method: "Runtime.evaluate",
            parameters: try JSONSerialization.data(withJSONObject: ["expression": expression]))
        let bytes = try await store.sendCommand(command, to: fixture.target, for: fixture.client)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private func withFixture(_ operation: (Fixture, BrowserExtensionDebuggerSessionStore) async throws -> Void)
        async throws
    {
        let fixture = Fixture(page: try await page())
        let store = BrowserExtensionDebuggerSessionStore(authorizeClient: { _ in true }) { [weak fixture] target in
            guard let fixture, target == fixture.target else { return .closed }
            fixture.resolutionCount += 1
            if fixture.isClosed { return .closed }
            return fixture.isRestricted ? .restricted : .available(fixture.page)
        }
        store.register(client: fixture.client, spaceID: fixture.space, displayName: "First extension")
        store.register(client: fixture.otherClient, spaceID: fixture.space, displayName: "Second extension")
        defer { store.shutdown() }
        try await operation(fixture, store)
    }

    private func page() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences)
        let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        page.isInspectable = true
        page.loadHTMLString("<!doctype html><title>Crest session test</title>", baseURL: nil)
        try await waitUntil {
            (try? await page.evaluateJavaScript("document.title")) as? String == "Crest session test"
        }
        return page
    }

    private func waitUntil(_ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try await !condition() {
            guard ContinuousClock.now < deadline else { throw BrowserWebInspectorProtocolError.timedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private final class Fixture {
        let space = SpaceID()
        let tab = TabID()
        var page: WKWebView
        var isRestricted = false
        var isClosed = false
        var resolutionCount = 0
        var target: BrowserExtensionDebuggerTarget { .init(spaceID: space, tabID: tab) }
        var client: BrowserExtensionServiceClientID { .scoped(extensionID: "first", spaceID: space) }
        var otherClient: BrowserExtensionServiceClientID { .scoped(extensionID: "second", spaceID: space) }
        init(page: WKWebView) { self.page = page }
    }

    private final class EventRecorder {
        var values: [BrowserExtensionDebuggerEvent] = []
    }
}
