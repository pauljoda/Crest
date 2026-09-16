import Foundation
import WebKit
import XCTest

@testable import Crest

/// What the emulated-header-rule broker will accept off the wire.
final class BrowserExtensionDeclarativeNetRequestBrokerRequestTests: XCTestCase {
    @MainActor
    func testBrokerRequiresCurrentConsentInsteadOfSupportedDeclarations() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(
            #"{"manifest_version":3,"name":"Consent probe","version":"1.0","permissions":["declarativeNetRequest"]}"#
                .utf8
        )
        .write(to: root.appending(path: "manifest.json"))
        let pool = BrowserExtensionControllerPool()
        let space = BrowserSession.preview.spaces[0]
        for (index, snapshot) in [
            BrowserExtensionPermissionSnapshot.empty,
            .init(grantedPermissions: ["declarativeNetRequest": .distantPast]),
            .init(
                grantedPermissions: ["declarativeNetRequest": .distantFuture],
                deniedPermissions: ["declarativeNetRequest": .distantFuture]),
        ].enumerated() {
            let context = try await pool.runtimeContextController.loadExtension(
                at: root, extensionID: "consent-\(index)", in: space, unsupportedAPIs: [],
                permissionSnapshot: snapshot, persistsRuntimeSummary: false, source: nil,
                capabilityBrokerGrantedPermissions: ["declarativeNetRequest"], allowsInternalCapabilityBroker: true)
            let authorization = try XCTUnwrap(
                pool.tabWindowCoordinator.verifiedNativeMessagingAuthorizations[ObjectIdentifier(context)])
            XCTAssertFalse(authorization.grants("declarativeNetRequest"))
            context.setPermissionStatus(.grantedExplicitly, for: .init(rawValue: "declarativeNetRequest"))
            XCTAssertTrue(authorization.grants("declarativeNetRequest"))
            context.setPermissionStatus(.deniedExplicitly, for: .init(rawValue: "declarativeNetRequest"))
            XCTAssertFalse(authorization.grants("declarativeNetRequest"))
            context.setPermissionStatus(.grantedExplicitly, for: .init(rawValue: "declarativeNetRequest"))
            try pool.controller(for: space).unload(context)
            XCTAssertFalse(authorization.grants("declarativeNetRequest"))
        }
    }

    func testSavedConsentUsesDenialPrecedenceAndExpiryForEveryCapability() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = BrowserExtensionPermissionSnapshot(
            grantedPermissions: [
                "idle": now, "declarativeNetRequest": .distantFuture,
                "notifications": .distantFuture, "menus": .distantFuture,
            ],
            deniedPermissions: [
                "declarativeNetRequest": .distantFuture,
                "notifications": .distantPast, "contextMenus": .distantFuture,
            ])
        let restored = try JSONDecoder().decode(
            BrowserExtensionPermissionSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(
            BrowserExtensionManagedPermissionPolicy.effectivePermissions(in: restored, now: now),
            ["notifications", "menus"])
    }

    @MainActor
    func testRevocationKeepsOtherSpaceGrantsAndBrokerClientOwnershipIntact() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(
            #"{"manifest_version":3,"name":"Space consent","version":"1.0","permissions":["declarativeNetRequest"]}"#
                .utf8
        )
        .write(to: root.appending(path: "manifest.json"))
        let pool = BrowserExtensionControllerPool()
        let spaces = BrowserSession.preview.spaces
        var contexts: [WKWebExtensionContext] = []
        for space in spaces.prefix(2) {
            contexts.append(
                try await pool.runtimeContextController.loadExtension(
                    at: root, extensionID: "space-consent", in: space, unsupportedAPIs: [],
                    permissionSnapshot: .init(grantedPermissions: ["declarativeNetRequest": .distantFuture]),
                    persistsRuntimeSummary: false, source: nil, allowsInternalCapabilityBroker: true))
        }
        contexts[0].setPermissionStatus(.deniedExplicitly, for: .init(rawValue: "declarativeNetRequest"))
        let work = try XCTUnwrap(
            pool.tabWindowCoordinator.verifiedNativeMessagingAuthorizations[ObjectIdentifier(contexts[0])])
        let personal = try XCTUnwrap(
            pool.tabWindowCoordinator.verifiedNativeMessagingAuthorizations[ObjectIdentifier(contexts[1])])
        XCTAssertFalse(work.grants("declarativeNetRequest"))
        XCTAssertTrue(personal.grants("declarativeNetRequest"))
        XCTAssertNotEqual(work.clientID, personal.clientID)
        pool.tabWindowCoordinator.declarativeNetRequestService = BrowserExtensionDeclarativeNetRequestStore(
            persistence: InMemoryBrowserExtensionDeclarativeNetRequestStore())
        var reply: Any?
        var replyError: Error?
        XCTAssertTrue(
            pool.tabWindowCoordinator.handleCapabilityBrokerDeclarativeNetRequest(
                ["api": "dnr.emulatedHeaderRules"],
                applicationIdentifier: BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier,
                controller: pool.controller(for: spaces[1]), extensionContext: contexts[1],
                replyHandler: { value, error in
                    reply = value
                    replyError = error
                }))
        XCTAssertNotNil(reply)
        XCTAssertNil(replyError)
        XCTAssertTrue(
            pool.tabWindowCoordinator.handleCapabilityBrokerDeclarativeNetRequest(
                ["api": "dnr.emulatedHeaderRules"],
                applicationIdentifier: BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier,
                controller: pool.controller(for: spaces[0]), extensionContext: contexts[1],
                replyHandler: { _, error in replyError = error }))
        XCTAssertNotNil(replyError)
    }

    func testBrowserManagedCapabilitiesAreIncludedInRequiredAccessReview() {
        let requested = BrowserExtensionManagedPermissionPolicy.requestedPermissions(
            native: ["storage"],
            manifest: [
                "permissions": ["idle", "identity", "tabGroups", "sidePanel", "offscreen"],
                "optional_permissions": ["debugger"], "sidebar_action": ["default_panel": "sidebar.html"],
            ])
        XCTAssertEqual(
            Set(requested), ["storage", "idle", "identity", "tabGroups", "sidePanel", "offscreen", "sidebarAction"])
        let reviewed = BrowserExtensionInstallationPermissionPolicy.reviewedRequiredAccess(
            permissions: requested, hosts: [])
        XCTAssertEqual(BrowserExtensionManagedPermissionPolicy.effectivePermissions(in: reviewed), Set(requested))
        XCTAssertFalse(BrowserExtensionManagedPermissionPolicy.effectivePermissions(in: .empty).contains("idle"))
    }

    func testSetRulesCarriesAWholeRulesetAndNamesWhichOne() throws {
        let request = try BrowserExtensionDeclarativeNetRequestBrokerRequest(message: [
            "api": "dnr.setEmulatedHeaderRules",
            "ruleset": "dynamic",
            "rules": [
                [
                    "id": 1,
                    "priority": 2,
                    "condition": ["urlFilter": "https://api.anthropic.com/*"],
                    "requestHeaders": [
                        ["header": "anthropic-client-platform", "operation": "set", "value": "ext"]
                    ],
                ]
            ],
        ])
        XCTAssertEqual(request.operation, .setRules)
        XCTAssertEqual(request.ruleset, .dynamic)
        XCTAssertEqual(request.rules.count, 1)
        XCTAssertEqual(request.rules[0].priority, 2)
        XCTAssertEqual(request.rules[0].requestHeaders.first?.header, "anthropic-client-platform")
    }

    func testAnEmptyRulesetIsHowARulesetIsCleared() throws {
        let request = try BrowserExtensionDeclarativeNetRequestBrokerRequest(message: [
            "api": "dnr.setEmulatedHeaderRules", "ruleset": "session", "rules": [[String: Any]](),
        ])
        XCTAssertEqual(request.ruleset, .session)
        XCTAssertTrue(request.rules.isEmpty)
    }

    func testReadingTheTableNamesNoRuleset() throws {
        let request = try BrowserExtensionDeclarativeNetRequestBrokerRequest(message: [
            "api": "dnr.emulatedHeaderRules"
        ])
        XCTAssertEqual(request.operation, .rules)
        XCTAssertNil(request.ruleset)
        XCTAssertTrue(request.rules.isEmpty)
    }

    func testAMalformedRequestIsRefusedRatherThanPartlyAccepted() {
        for message: [String: Any] in [
            ["api": "dnr.unknown"],
            ["api": "dnr.setEmulatedHeaderRules", "rules": [[String: Any]]()],
            ["api": "dnr.setEmulatedHeaderRules", "ruleset": "static", "rules": [[String: Any]]()],
            ["api": "dnr.setEmulatedHeaderRules", "ruleset": "session"],
            [
                "api": "dnr.setEmulatedHeaderRules", "ruleset": "session",
                "rules": [["id": 1, "requestHeaders": [[String: Any]]()]],
            ],
        ] {
            XCTAssertThrowsError(
                try BrowserExtensionDeclarativeNetRequestBrokerRequest(message: message),
                String(describing: message))
        }
    }

    func testEitherDeclarativeNetRequestPermissionReachesTheEmulation() throws {
        let required = BrowserExtensionDeclarativeNetRequestBrokerRequest.requiredCapabilities
        XCTAssertEqual(
            required, ["declarativeNetRequest", "declarativeNetRequestWithHostAccess"])
        let contract = try XCTUnwrap(
            BrowserExtensionAPICompatibilityMatrix.contracts.first {
                $0.namespace == "declarativeNetRequest"
            })
        // The broker only ever grants a permission the matrix names for it.
        XCTAssertEqual(contract.capabilityBrokerPermissions, required)
    }
}
