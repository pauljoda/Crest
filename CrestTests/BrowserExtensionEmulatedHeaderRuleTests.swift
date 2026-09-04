import Foundation
import XCTest

@testable import Crest

/// The condition grammar and the header partition behind Crest's
/// `modifyHeaders` emulation. The compatibility runtime mirrors both in
/// JavaScript; these are the cases that say what "mirror" means.
final class BrowserExtensionEmulatedHeaderRuleTests: XCTestCase {
    private func rule(
        id: Int = 1,
        priority: Int = 1,
        _ condition: BrowserExtensionEmulatedHeaderRule.Condition,
        headers: [BrowserExtensionEmulatedHeaderRule.HeaderModification] = [
            .init(header: "x-crest", operation: .set, value: "1")
        ]
    ) -> BrowserExtensionEmulatedHeaderRule {
        BrowserExtensionEmulatedHeaderRule(
            id: id, priority: priority, condition: condition, requestHeaders: headers)
    }

    private func matches(
        _ condition: BrowserExtensionEmulatedHeaderRule.Condition,
        _ url: String,
        method: String = "get"
    ) -> Bool {
        BrowserExtensionEmulatedHeaderRuleMatcher.matches(condition, url: url, method: method)
    }

    func testURLFilterWildcardsSeparatorsAndAnchors() {
        // A bare filter is a substring match, case-insensitive by default.
        XCTAssertTrue(matches(.init(urlFilter: "anthropic"), "https://API.ANTHROPIC.com/v1"))
        XCTAssertFalse(
            matches(
                .init(urlFilter: "anthropic", isURLFilterCaseSensitive: true),
                "https://API.ANTHROPIC.com/v1"))

        XCTAssertTrue(
            matches(.init(urlFilter: "https://api.anthropic.com/*"), "https://api.anthropic.com/v1/messages"))
        XCTAssertFalse(
            matches(.init(urlFilter: "https://api.anthropic.com/*"), "https://example.test/api.anthropic.com/"))

        // `|` anchors the start and the end of the whole URL.
        XCTAssertTrue(matches(.init(urlFilter: "|https://a.test/x|"), "https://a.test/x"))
        XCTAssertFalse(matches(.init(urlFilter: "|https://a.test/x|"), "https://a.test/xy"))
        XCTAssertFalse(matches(.init(urlFilter: "|api.test"), "https://api.test/"))

        // `||` anchors to a host or any of its parent-labelled subdomains.
        XCTAssertTrue(matches(.init(urlFilter: "||anthropic.com"), "https://api.anthropic.com/v1"))
        XCTAssertTrue(matches(.init(urlFilter: "||anthropic.com"), "https://anthropic.com/"))
        XCTAssertFalse(matches(.init(urlFilter: "||anthropic.com"), "https://notanthropic.com/"))

        // `^` is a separator: anything outside [A-Za-z0-9_-.%], or the end.
        XCTAssertTrue(matches(.init(urlFilter: "||api.test^"), "https://api.test/v1"))
        XCTAssertTrue(matches(.init(urlFilter: "||api.test^"), "https://api.test"))
        XCTAssertFalse(matches(.init(urlFilter: "||api.test^"), "https://api.test.example/"))
    }

    func testRegexFilterAppliesAndAnUncompilablePatternMatchesNothing() {
        XCTAssertTrue(
            matches(
                .init(regexFilter: #"^https://api\.anthropic\.com/v\d+/"#),
                "https://api.anthropic.com/v1/messages"))
        XCTAssertFalse(
            matches(
                .init(regexFilter: #"^https://api\.anthropic\.com/v\d+/"#),
                "https://api.anthropic.com/health"))
        XCTAssertFalse(matches(.init(regexFilter: "([unclosed"), "https://api.test/"))
    }

    func testResourceTypesAndMethodsDecideWhetherAnExtensionRequestQualifies() {
        XCTAssertTrue(matches(.init(resourceTypes: ["xmlhttprequest", "other"]), "https://a.test/"))
        XCTAssertTrue(matches(.init(resourceTypes: ["other"]), "https://a.test/"))
        XCTAssertFalse(matches(.init(resourceTypes: ["image", "media"]), "https://a.test/"))
        XCTAssertFalse(
            matches(.init(excludedResourceTypes: ["xmlhttprequest"]), "https://a.test/"))
        // No resource types at all means the rule is not narrowed by type.
        XCTAssertTrue(matches(.init(urlFilter: "a.test"), "https://a.test/"))

        XCTAssertTrue(matches(.init(requestMethods: ["post"]), "https://a.test/", method: "POST"))
        XCTAssertFalse(matches(.init(requestMethods: ["post"]), "https://a.test/", method: "GET"))
        XCTAssertFalse(
            matches(.init(excludedRequestMethods: ["post"]), "https://a.test/", method: "post"))
    }

    func testTheHighestPriorityRuleOwnsAHeaderAndTiesGoToTheLowerRuleID() {
        let modifications = BrowserExtensionEmulatedHeaderRuleMatcher.modifications(
            applying: [
                rule(
                    id: 9, priority: 1, .init(urlFilter: "*"),
                    headers: [
                        .init(header: "x-pick", operation: .set, value: "low"),
                        .init(header: "x-tie", operation: .set, value: "nine"),
                    ]),
                rule(
                    id: 3, priority: 5, .init(urlFilter: "*"),
                    headers: [.init(header: "X-Pick", operation: .set, value: "high")]),
                rule(
                    id: 4, priority: 1, .init(urlFilter: "*"),
                    headers: [.init(header: "x-tie", operation: .set, value: "four")]),
                // Filtered out by its condition, so it never competes.
                rule(
                    id: 1, priority: 99, .init(urlFilter: "https://elsewhere.test/"),
                    headers: [.init(header: "x-pick", operation: .set, value: "ignored")]),
            ],
            url: "https://api.anthropic.com/v1/messages",
            method: "post"
        )
        XCTAssertEqual(modifications.map(\.header), ["X-Pick", "x-tie"])
        XCTAssertEqual(modifications.map(\.value), ["high", "four"])
    }

    func testTheAcceptedHeaderListIsWebKitsAndCustomNamesArePartitionedOut() {
        let policy = BrowserExtensionDeclarativeNetRequestHeaderPolicy.self
        XCTAssertEqual(policy.webKitAcceptedHeaderNames.count, 93)
        XCTAssertEqual(policy.webKitAcceptedHeaderNames.first, "accept")
        XCTAssertEqual(policy.webKitAcceptedHeaderNames.last, "icy-metadata")
        XCTAssertTrue(policy.webKitAcceptsHeaderName("Accept-Language"))
        XCTAssertTrue(policy.webKitAcceptsHeaderName("USER-AGENT"))
        XCTAssertFalse(policy.webKitAcceptsHeaderName("anthropic-client-platform"))

        let (accepted, emulated) = policy.partition(requestHeaders: [
            .init(header: "User-Agent", operation: .set, value: "claude-browser/1"),
            .init(header: "anthropic-client-platform", operation: .set, value: "ext"),
            .init(header: "anthropic-client-version", operation: .set, value: "1.2.3"),
        ])
        XCTAssertEqual(accepted.map(\.header), ["User-Agent"])
        XCTAssertEqual(
            emulated.map(\.header), ["anthropic-client-platform", "anthropic-client-version"])
    }

    func testFetchForbiddenNamesCoverTheSpecPrefixesAndUserAgent() {
        let policy = BrowserExtensionDeclarativeNetRequestHeaderPolicy.self
        for name in ["User-Agent", "host", "Origin", "Cookie", "referer", "Content-Length"] {
            XCTAssertTrue(policy.fetchForbidsHeaderName(name), name)
        }
        XCTAssertTrue(policy.fetchForbidsHeaderName("Sec-Fetch-Mode"))
        XCTAssertTrue(policy.fetchForbidsHeaderName("Proxy-Authorization"))
        XCTAssertFalse(policy.fetchForbidsHeaderName("anthropic-client-platform"))
        XCTAssertFalse(policy.fetchForbidsHeaderName("authorization"))
    }

    func testTheWirePayloadRoundTripsAndRejectsAnUnusableRule() throws {
        let payload: [String: Any] = [
            "id": 1,
            "priority": 4,
            "condition": [
                "urlFilter": "https://api.anthropic.com/*",
                "isUrlFilterCaseSensitive": true,
                "resourceTypes": ["xmlhttprequest", "other"],
                "requestMethods": ["post"],
            ],
            "requestHeaders": [
                ["header": "anthropic-client-platform", "operation": "set", "value": "ext"],
                ["header": "x-drop", "operation": "remove"],
            ],
        ]
        let decoded = try BrowserExtensionEmulatedHeaderRule(payload: payload)
        XCTAssertEqual(decoded.id, 1)
        XCTAssertEqual(decoded.priority, 4)
        XCTAssertTrue(decoded.condition.isURLFilterCaseSensitive)
        XCTAssertEqual(decoded.condition.resourceTypes, ["xmlhttprequest", "other"])
        XCTAssertEqual(decoded.requestHeaders.map(\.operation), [.set, .remove])
        XCTAssertNil(decoded.requestHeaders[1].value)
        XCTAssertEqual(try BrowserExtensionEmulatedHeaderRule(payload: decoded.payload), decoded)

        // No id, no usable operation, a value on a remove, and a missing value
        // on a set are all rejected rather than stored half-formed.
        XCTAssertThrowsError(try BrowserExtensionEmulatedHeaderRule(payload: ["requestHeaders": []]))
        XCTAssertThrowsError(try BrowserExtensionEmulatedHeaderRule(payload: ["id": 1]))
        XCTAssertThrowsError(
            try BrowserExtensionEmulatedHeaderRule(
                payload: ["id": 1, "requestHeaders": [["header": "x", "operation": "shout"]]]))
        XCTAssertThrowsError(
            try BrowserExtensionEmulatedHeaderRule(
                payload: ["id": 1, "requestHeaders": [["header": "x", "operation": "set"]]]))
    }
}
