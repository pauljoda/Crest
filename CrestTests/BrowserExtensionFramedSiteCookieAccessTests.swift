import Foundation
import WebKit
import XCTest

@testable import Crest

/// The trigger half of the rule, exercised against a real
/// `WKWebExtensionContext` and its granted match patterns.
///
/// The subframe gate itself is not covered here: `WKNavigationAction` has no
/// constructible form, so the `WKNavigationAction` overload can only be reached
/// from a live web view. What is covered is every decision that follows it —
/// scheme, host, and host permission.
@MainActor
final class BrowserExtensionFramedSiteCookieAccessTests: XCTestCase {
    private let space = SpaceID()

    func testAPermittedSiteIsRelaxedForTheFramingExtensionAndSpace() async throws {
        let (access, store, jar) = try await makeAccess(granting: "https://claude.ai/*")
        let url = URL(string: "https://claude.ai/cic/new?surface=cic_sidepanel")

        let host = try XCTUnwrap(access.hostRequiringRewrite(for: url))
        await access.relaxCookies(for: host)

        XCTAssertEqual(host, "claude.ai")
        XCTAssertEqual(jar.relaxRequests[space], ["claude.ai"])
        XCTAssertEqual(store.relaxedHosts(in: space), ["claude.ai"])
    }

    func testASiteWithoutHostPermissionIsLeftToWebKit() async throws {
        let (access, _, _) = try await makeAccess(granting: "https://claude.ai/*")

        XCTAssertNil(access.hostRequiringRewrite(for: URL(string: "https://example.com/tracker")))
    }

    func testNonWebFramesAreNeverRelaxed() async throws {
        let (access, _, _) = try await makeAccess(granting: "https://claude.ai/*")

        // The last one shares the permitted host but not a cookie-bearing
        // scheme, so the scheme gate is what has to refuse it.
        for raw in ["about:blank", "data:text/html,<p>hi</p>", "chrome-extension://claude.ai/x.html"] {
            XCTAssertNil(
                access.hostRequiringRewrite(for: URL(string: raw)),
                "\(raw) must not trigger a rewrite"
            )
        }
        XCTAssertNil(access.hostRequiringRewrite(for: nil))
    }

    func testNoServiceMeansNoSeamAtAll() async throws {
        let context = try await makeContext()
        let access = BrowserExtensionFramedSiteCookieAccess(
            configuration: makeConfiguration(context),
            spaceID: space,
            service: nil
        )

        XCTAssertNil(access)
    }

    // MARK: - Helpers

    private func makeAccess(
        granting pattern: String
    ) async throws -> (
        BrowserExtensionFramedSiteCookieAccess,
        BrowserExtensionCookieAccessStore,
        InMemoryBrowserExtensionCookieJar
    ) {
        let context = try await makeContext()
        context.setPermissionStatus(
            .grantedExplicitly,
            for: try WKWebExtension.MatchPattern(string: pattern)
        )
        let jar = InMemoryBrowserExtensionCookieJar()
        let store = BrowserExtensionCookieAccessStore(cookieJar: jar)
        let access = try XCTUnwrap(
            BrowserExtensionFramedSiteCookieAccess(
                configuration: makeConfiguration(context),
                spaceID: space,
                service: store
            )
        )
        return (access, store, jar)
    }

    private func makeContext() async throws -> WKWebExtensionContext {
        WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: fixtureURL))
    }

    private func makeConfiguration(
        _ context: WKWebExtensionContext
    ) -> BrowserExtensionPageConfiguration {
        BrowserExtensionPageConfiguration(
            baseURL: context.baseURL,
            context: context,
            webViewConfiguration: WKWebViewConfiguration(),
            clientID: .scoped(extensionID: "side-panel-probe", spaceID: space)
        )
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/SidePanelProbeExtension", directoryHint: .isDirectory)
    }
}
