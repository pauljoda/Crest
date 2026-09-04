import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionWebAuthFlowHostTests: XCTestCase {
    private static let extensionName = "Crest Identity Fixture"
    private static let redirectOrigin = "https://fixtureextensionid.chromiumapp.org"

    /// The shape the Claude extension's silent re-authentication takes: a
    /// provider page that redirects from JavaScript, no window, and the full
    /// callback URL — code and state intact — handed back.
    func testJavaScriptRedirectResolvesWithTheWholeCallbackURL() async throws {
        let host = makeHost()
        let url = try await host.runWebAuthFlow(
            makeRequest(
                html: """
                    <!doctype html><meta charset="utf-8"><script>
                    location.replace('\(Self.redirectOrigin)/?code=abc123&state=xyz#extra');
                    </script>
                    """,
                abortsOnLoad: false
            )
        )
        XCTAssertEqual(
            url.absoluteString,
            "\(Self.redirectOrigin)/?code=abc123&state=xyz#extra")
        await assertFlowWasTornDown(host)
    }

    /// A redirect that happens after the page settles still completes the
    /// flow, which is exactly why `abortOnLoadForNonInteractive` exists.
    func testDeferredRedirectCompletesWhenAbortOnLoadIsWaived() async throws {
        let host = makeHost()
        let url = try await host.runWebAuthFlow(
            makeRequest(
                html: """
                    <!doctype html><meta charset="utf-8"><title>Authorizing</title><script>
                    window.addEventListener('load', () => setTimeout(
                        () => location.replace('\(Self.redirectOrigin)/?code=deferred'), 50));
                    </script>
                    """,
                abortsOnLoad: false
            )
        )
        XCTAssertEqual(url.absoluteString, "\(Self.redirectOrigin)/?code=deferred")
        await assertFlowWasTornDown(host)
    }

    /// Chrome's default: a non-interactive flow ends the moment a page it
    /// would have had to show finishes loading.
    func testNonInteractivePageThatFinishesLoadingNeedsInteraction() async throws {
        let host = makeHost()
        await assertFailure(
            .interactionRequired,
            from: {
                try await host.runWebAuthFlow(
                    self.makeRequest(
                        html: "<!doctype html><meta charset=\"utf-8\"><title>Sign in</title>Sign in"
                    )
                )
            }
        )
        await assertFlowWasTornDown(host)
    }

    /// The deadline is the other half of the same rule: a page that waives the
    /// load abort still cannot keep an invisible web view forever.
    func testNonInteractiveDeadlineNeedsInteraction() async throws {
        let host = makeHost()
        await assertFailure(
            .interactionRequired,
            from: {
                try await host.runWebAuthFlow(
                    self.makeRequest(
                        html: """
                            <!doctype html><meta charset="utf-8"><title>Waiting</title><script>
                            setTimeout(() => {}, 30000);
                            </script>
                            """,
                        abortsOnLoad: false,
                        timeout: 0.4
                    )
                )
            }
        )
        await assertFlowWasTornDown(host)
    }

    /// A Space with no extension controller yet has no data store to run the
    /// flow in. Chrome reports every unreachable authorization page the same
    /// way, and so does this.
    func testAMissingDataStoreReportsChromesLoadFailure() async throws {
        let host = BrowserExtensionWebAuthFlowHost(
            websiteDataStore: { _ in nil },
            profile: { _ in BrowsingProfile() },
            anchorWindow: { nil }
        )
        await assertFailure(
            .pageLoadFailure,
            from: { try await host.runWebAuthFlow(self.makeRequest(html: "<!doctype html>")) }
        )
    }

    func testAnUnreachableAuthorizationPageReportsChromesLoadFailure() async throws {
        let host = makeHost()
        var request = makeRequest(html: "<!doctype html>")
        request = BrowserExtensionWebAuthFlowRequest(
            url: try XCTUnwrap(URL(string: "https://crest-identity.invalid/authorize")),
            redirectOrigin: request.redirectOrigin,
            isInteractive: false,
            abortsOnLoadForNonInteractive: true,
            nonInteractiveTimeout: 5,
            spaceID: request.spaceID,
            extensionID: request.extensionID,
            extensionDisplayName: request.extensionDisplayName
        )
        await assertFailure(.pageLoadFailure, from: { try await host.runWebAuthFlow(request) })
        await assertFlowWasTornDown(host)
    }

    private func makeHost() -> BrowserExtensionWebAuthFlowHost {
        BrowserExtensionWebAuthFlowHost(
            websiteDataStore: { _ in .nonPersistent() },
            profile: { _ in BrowsingProfile() },
            anchorWindow: { nil }
        )
    }

    private func makeRequest(
        html: String,
        interactive: Bool = false,
        abortsOnLoad: Bool = true,
        timeout: TimeInterval = 5
    ) -> BrowserExtensionWebAuthFlowRequest {
        let encoded =
            html.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return BrowserExtensionWebAuthFlowRequest(
            url: URL(string: "data:text/html;charset=utf-8,\(encoded)")!,
            redirectOrigin: Self.redirectOrigin,
            isInteractive: interactive,
            abortsOnLoadForNonInteractive: abortsOnLoad,
            nonInteractiveTimeout: timeout,
            spaceID: SpaceID(),
            extensionID: "fixtureextensionid",
            extensionDisplayName: Self.extensionName
        )
    }

    private func assertFailure(
        _ expected: BrowserExtensionIdentityBrokerError,
        from operation: () async throws -> URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            let url = try await operation()
            XCTFail("The flow resolved with \(url) instead of failing.", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? BrowserExtensionIdentityBrokerError, expected, file: file, line: line)
        }
    }

    /// The session — and with it the web view on somebody's cookie jar — does
    /// not outlive the flow. The host holds it weakly, so this is deallocation
    /// rather than a flag somebody remembered to clear. A silent flow is
    /// invisible by design, which is exactly why a leaked one would go
    /// unnoticed without this.
    private func assertFlowWasTornDown(
        _ host: BrowserExtensionWebAuthFlowHost,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<40 {
            if !host.isRunningFlow { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(host.isRunningFlow, "The flow outlived its answer.", file: file, line: line)
        XCTAssertFalse(
            NSApp.windows.contains { $0.title == Self.extensionName && $0.isVisible },
            "A silent flow must never leave a visible authorization window.",
            file: file,
            line: line
        )
    }
}
