import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionDebuggerBrokerTests: XCTestCase {
    func testWebKitDoesNotOwnDebuggerPermissionState() async throws {
        let webExtension = try await WKWebExtension(resourceBaseURL: fixtureURL)
        let context = WKWebExtensionContext(for: webExtension)
        let permission = WKWebExtension.Permission(rawValue: "debugger")
        XCTAssertFalse(context.hasPermission(permission))
        context.setPermissionStatus(.grantedExplicitly, for: permission)
        XCTAssertFalse(context.hasPermission(permission))
        XCTAssertEqual(context.permissionStatus(for: permission), .unknown)
        context.setPermissionStatus(.deniedExplicitly, for: permission)
        XCTAssertFalse(context.hasPermission(permission))
        XCTAssertEqual(context.permissionStatus(for: permission), .unknown)
    }

    func testDebuggerRequiresAnExplicitGrantAndRetainsItAcrossNativePermissionChangesAndReload() async throws {
        try await withPool { pool in
            let space = BrowserSession.preview.spaces[0]
            let summary = try await pool.loadUnpackedExtension(from: self.fixtureURL, in: space)
            let context = try XCTUnwrap(pool.loadedContext(extensionID: summary.id, in: space.id))
            XCTAssertTrue(summary.requestedPermissions.contains("debugger"))
            XCTAssertEqual(pool.permissionDecision(for: "debugger", extensionID: summary.id, in: space.id), .ask)
            pool.setPermissionDecision(.allow, for: "debugger", extensionID: summary.id, in: space.id)
            XCTAssertEqual(pool.permissionDecision(for: "debugger", extensionID: summary.id, in: space.id), .allow)
            XCTAssertTrue(pool.permissionController.hasBrowserManagedPermission("debugger", for: context))
            context.setPermissionStatus(.grantedExplicitly, for: .storage)
            pool.persistPermissionState(extensionID: summary.id, in: space.id)
            XCTAssertEqual(pool.permissionDecision(for: "debugger", extensionID: summary.id, in: space.id), .allow)
            XCTAssertNotNil(pool.extensions(in: space.id).first?.permissionSnapshot.grantedPermissions["debugger"])
            try await pool.setExtensionEnabled(false, extensionID: summary.id, in: space)
            XCTAssertFalse(pool.permissionController.hasBrowserManagedPermission("debugger", for: context))
            try await pool.setExtensionEnabled(true, extensionID: summary.id, in: space)
            let restored = try XCTUnwrap(pool.loadedContext(extensionID: summary.id, in: space.id))
            XCTAssertFalse(restored === context)
            XCTAssertTrue(pool.permissionController.hasBrowserManagedPermission("debugger", for: restored))
        }
    }

    func testDebuggerGrantRevokeAndAskAreIndependentForEachSpace() async throws {
        try await withPool { pool in
            let work = BrowserSession.preview.spaces[0]
            let personal = BrowserSession.preview.spaces[1]
            let installed = try await pool.loadUnpackedExtension(from: self.fixtureURL, in: work)
            _ = try await pool.loadUnpackedExtension(from: self.fixtureURL, in: personal)
            let workContext = try XCTUnwrap(pool.loadedContext(extensionID: installed.id, in: work.id))
            let personalContext = try XCTUnwrap(pool.loadedContext(extensionID: installed.id, in: personal.id))
            pool.setPermissionDecision(.allow, for: "debugger", extensionID: installed.id, in: work.id)
            pool.setPermissionDecision(.block, for: "debugger", extensionID: installed.id, in: personal.id)
            XCTAssertTrue(pool.permissionController.hasBrowserManagedPermission("debugger", for: workContext))
            XCTAssertFalse(pool.permissionController.hasBrowserManagedPermission("debugger", for: personalContext))
            XCTAssertEqual(pool.permissionDecision(for: "debugger", extensionID: installed.id, in: personal.id), .block)
            pool.setPermissionDecision(.block, for: "debugger", extensionID: installed.id, in: work.id)
            XCTAssertFalse(pool.permissionController.hasBrowserManagedPermission("debugger", for: workContext))
            pool.setPermissionDecision(.ask, for: "debugger", extensionID: installed.id, in: work.id)
            XCTAssertEqual(pool.permissionDecision(for: "debugger", extensionID: installed.id, in: work.id), .ask)
            XCTAssertNil(pool.extensions(in: work.id).first?.permissionSnapshot.grantedPermissions["debugger"])
            XCTAssertNil(pool.extensions(in: work.id).first?.permissionSnapshot.deniedPermissions["debugger"])
            XCTAssertEqual(pool.permissionDecision(for: "debugger", extensionID: installed.id, in: personal.id), .block)
        }
    }

    func testExpiredOrConflictingDebuggerGrantsDoNotAuthorizeAccess() async throws {
        try await withPool { pool in
            let space = BrowserSession.preview.spaces[0]
            let context = try await pool.loadExtension(
                at: self.fixtureURL, extensionID: "expired-debugger", in: space,
                permissionSnapshot: .init(grantedPermissions: ["debugger": .distantPast]))
            XCTAssertFalse(pool.permissionController.hasBrowserManagedPermission("debugger", for: context))
            _ = pool.permissionController.apply(
                .init(
                    grantedPermissions: ["debugger": .distantFuture], deniedPermissions: ["debugger": .distantFuture]),
                to: context)
            XCTAssertFalse(pool.permissionController.hasBrowserManagedPermission("debugger", for: context))
        }
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/DebuggerPermissionProbeExtension", directoryHint: .isDirectory)
    }

    func testRevokingTheBrowserManagedGrantImmediatelyCancelsAnAttachedDebugger() async throws {
        try await withPool { pool in
            let space = BrowserSession.preview.spaces[0]
            let installed = try await pool.loadUnpackedExtension(from: self.fixtureURL, in: space)
            let context = try XCTUnwrap(pool.loadedContext(extensionID: installed.id, in: space.id))
            let client = BrowserExtensionServiceClientID.scoped(extensionID: installed.id, spaceID: space.id)
            let target = BrowserExtensionDebuggerTarget(spaceID: space.id, tabID: TabID())
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences)
            let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
            page.isInspectable = true
            page.loadHTMLString("<!doctype html><title>Permission revocation</title>", baseURL: nil)
            try await self.waitUntil {
                (try? await page.evaluateJavaScript("document.title")) as? String == "Permission revocation"
            }
            let store = BrowserExtensionDebuggerSessionStore(authorizeClient: { requested in
                requested == client && pool.permissionController.hasBrowserManagedPermission("debugger", for: context)
            }) { requested in requested == target ? .available(page) : .closed }
            defer { store.shutdown() }
            store.register(client: client, spaceID: space.id, displayName: installed.displayName)
            pool.permissionController.browserManagedPermissionsDidChange = { changed in
                if changed === context { store.reconcileTargets() }
            }
            defer { pool.permissionController.browserManagedPermissionsDidChange = nil }
            do {
                try await store.attach(to: target, for: client, requiredVersion: "1.3")
                XCTFail("A registration without the user's grant must not attach.")
            } catch BrowserExtensionDebuggerError.accessDenied {}
            pool.setPermissionDecision(.allow, for: "debugger", extensionID: installed.id, in: space.id)
            try await store.attach(to: target, for: client, requiredVersion: "1.3")
            let stopped = self.expectation(description: "Permission revocation cancels pending evaluation")
            let request = Task {
                do {
                    _ = try await store.sendCommand(
                        .init(
                            method: "Runtime.evaluate",
                            parameters: Data(
                                #"{"expression":"globalThis.crestPendingStarted=true; new Promise(() => {})","awaitPromise":true}"#
                                    .utf8)),
                        to: target, for: client)
                    XCTFail("Revoking access must reject pending commands.")
                } catch {
                    XCTAssertEqual(error as? BrowserExtensionDebuggerError, .detachedWhileHandling)
                }
                stopped.fulfill()
            }
            defer { request.cancel() }
            try await self.waitUntil {
                (try? await page.evaluateJavaScript("globalThis.crestPendingStarted === true")) as? Bool == true
            }
            pool.setPermissionDecision(.block, for: "debugger", extensionID: installed.id, in: space.id)
            XCTAssertTrue(store.sessions.isEmpty)
            await self.fulfillment(of: [stopped], timeout: 5)
        }
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await !predicate() {
            guard ContinuousClock.now < deadline else { throw BrowserWebInspectorProtocolError.timedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func withPool(_ operation: (BrowserExtensionControllerPool) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "crest-debugger-permission-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = BrowserExtensionControllerPool(packageStore: BrowserExtensionPackageStore(rootURL: root))
        try await operation(pool)
    }
}
