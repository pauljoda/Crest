import Foundation
import XCTest

@testable import Crest

/// What the emulated-header-rule broker will accept off the wire.
final class BrowserExtensionDeclarativeNetRequestBrokerRequestTests: XCTestCase {
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
