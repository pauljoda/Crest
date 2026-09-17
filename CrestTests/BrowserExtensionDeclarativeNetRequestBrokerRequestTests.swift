import Foundation
import XCTest

@testable import Crest

/// What the emulated-header-rule broker will accept off the wire.
final class BrowserExtensionDeclarativeNetRequestBrokerRequestTests: XCTestCase {
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
}
