import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionWebAuthenticationServiceTests: XCTestCase {
    private func callback(_ prefix: String) throws
        -> BrowserExtensionWebAuthenticationCallback
    {
        BrowserExtensionWebAuthenticationCallback(
            redirectPrefix: try XCTUnwrap(URL(string: prefix))
        )
    }

    private func request(
        callback: BrowserExtensionWebAuthenticationCallback,
        prefersEphemeralSession: Bool = false
    ) throws -> BrowserExtensionWebAuthenticationRequest {
        BrowserExtensionWebAuthenticationRequest(
            authorizationURL: try XCTUnwrap(
                URL(string: "https://provider.example/authorize?client_id=1")
            ),
            callback: callback,
            prefersEphemeralSession: prefersEphemeralSession
        )
    }

    private func service(
        outcome: Result<URL, BrowserExtensionWebAuthenticationError>,
        associatedHosts: Set<String> = []
    ) -> (
        service: BrowserExtensionWebAuthenticationService,
        session: InMemoryBrowserExtensionWebAuthenticationSession
    ) {
        let session = InMemoryBrowserExtensionWebAuthenticationSession(
            outcome: outcome
        )
        return (
            BrowserExtensionWebAuthenticationService(
                session: session,
                associatedWebCredentialHosts: associatedHosts
            ),
            session
        )
    }

    // MARK: - Callback matching

    func testCallbackMatchesOnPrefixAndIgnoresAuthorityCase() throws {
        let callback = try callback("https://abcdef.chromiumapp.org/")

        XCTAssertTrue(
            callback.matches(
                try XCTUnwrap(
                    URL(string: "https://abcdef.chromiumapp.org/?code=xyz")
                )
            )
        )
        XCTAssertTrue(
            callback.matches(
                try XCTUnwrap(
                    URL(string: "HTTPS://ABCDEF.CHROMIUMAPP.ORG/callback")
                )
            )
        )
        XCTAssertFalse(
            callback.matches(
                try XCTUnwrap(URL(string: "https://evil.example/?code=xyz"))
            )
        )
        XCTAssertFalse(
            callback.matches(
                try XCTUnwrap(URL(string: "http://abcdef.chromiumapp.org/"))
            )
        )
    }

    func testCallbackPathActsAsAPrefix() throws {
        let callback = try callback("https://app.example/oauth")

        XCTAssertTrue(
            callback.matches(
                try XCTUnwrap(URL(string: "https://app.example/oauth/done"))
            )
        )
        XCTAssertFalse(
            callback.matches(
                try XCTUnwrap(URL(string: "https://app.example/other"))
            )
        )
    }

    func testCustomSchemeCallbackIsRecognized() throws {
        let callback = try callback("com.example.app:/oauth")

        XCTAssertFalse(callback.usesWebScheme)
        XCTAssertEqual(callback.scheme, "com.example.app")
        XCTAssertTrue(
            callback.matches(
                try XCTUnwrap(URL(string: "com.example.app:/oauth?code=1"))
            )
        )
    }

    // MARK: - Serviceability

    /// The headline constraint: Crest cannot be an associated domain for
    /// `chromiumapp.org`, so the system session cannot watch for that redirect.
    func testChromiumAppRedirectsAreRejectedAsUnsupported() async throws {
        let (service, session) = service(
            outcome: .success(
                try XCTUnwrap(URL(string: "https://abcdef.chromiumapp.org/?code=1"))
            )
        )
        let request = try request(
            callback: try callback("https://abcdef.chromiumapp.org/")
        )

        do {
            _ = try await service.launch(request)
            XCTFail("Expected an unsupported-callback failure.")
        } catch let error as BrowserExtensionWebAuthenticationError {
            XCTAssertEqual(error, .unsupportedCallback)
        }
        XCTAssertEqual(session.startCount, 0)
    }

    func testAnAssociatedHTTPSHostIsServiced() async throws {
        let redirectURL = try XCTUnwrap(
            URL(string: "https://auth.crestbrowser.example/oauth?code=1")
        )
        let (service, session) = service(
            outcome: .success(redirectURL),
            associatedHosts: ["auth.crestbrowser.example"]
        )
        let request = try request(
            callback: try callback("https://auth.crestbrowser.example/oauth")
        )

        let result = try await service.launch(request)

        XCTAssertEqual(result, redirectURL)
        XCTAssertEqual(session.startCount, 1)
    }

    func testACustomSchemeNeedsNoAssociation() async throws {
        let redirectURL = try XCTUnwrap(
            URL(string: "com.example.app:/oauth?code=1")
        )
        let (service, session) = service(outcome: .success(redirectURL))
        let request = try request(
            callback: try callback("com.example.app:/oauth")
        )

        let result = try await service.launch(request)

        XCTAssertEqual(result, redirectURL)
        XCTAssertEqual(session.startCount, 1)
    }

    func testPlainHTTPIsNeverServiced() async throws {
        let (service, session) = service(
            outcome: .success(try XCTUnwrap(URL(string: "http://app.example/cb"))),
            associatedHosts: ["app.example"]
        )
        let request = try request(callback: try callback("http://app.example/cb"))

        do {
            _ = try await service.launch(request)
            XCTFail("Expected an unsupported-callback failure.")
        } catch let error as BrowserExtensionWebAuthenticationError {
            XCTAssertEqual(error, .unsupportedCallback)
        }
        XCTAssertEqual(session.startCount, 0)
    }

    // MARK: - Request forwarding

    func testTheRequestReachesTheSessionVerbatim() async throws {
        let (service, session) = service(
            outcome: .success(
                try XCTUnwrap(URL(string: "com.example.app:/oauth?code=1"))
            )
        )
        let callback = try callback("com.example.app:/oauth")
        let request = try request(
            callback: callback,
            prefersEphemeralSession: true
        )

        _ = try await service.launch(request)

        XCTAssertEqual(
            session.startedAuthorizationURLs,
            [request.authorizationURL]
        )
        XCTAssertEqual(session.startedCallbacks, [callback])
        XCTAssertEqual(session.startedEphemeralPreferences, [true])
    }

    // MARK: - Failures

    func testCancellationSurfacesAsATypedError() async throws {
        let (service, _) = service(outcome: .failure(.userCanceled))
        let request = try request(
            callback: try callback("com.example.app:/oauth")
        )

        do {
            _ = try await service.launch(request)
            XCTFail("Expected a cancellation failure.")
        } catch let error as BrowserExtensionWebAuthenticationError {
            XCTAssertEqual(error, .userCanceled)
        }
    }

    func testPresentationFailureSurfacesAsATypedError() async throws {
        let (service, _) = service(outcome: .failure(.presentationFailure))
        let request = try request(
            callback: try callback("com.example.app:/oauth")
        )

        do {
            _ = try await service.launch(request)
            XCTFail("Expected a presentation failure.")
        } catch let error as BrowserExtensionWebAuthenticationError {
            XCTAssertEqual(error, .presentationFailure)
        }
    }

    /// A provider that redirects somewhere other than the awaited prefix must
    /// not have that URL — or anything in its fragment — handed to the
    /// extension.
    func testARedirectOutsideThePrefixIsRefused() async throws {
        let (service, _) = service(
            outcome: .success(
                try XCTUnwrap(URL(string: "com.example.app:/elsewhere?code=1"))
            )
        )
        let request = try request(
            callback: try callback("com.example.app:/oauth")
        )

        do {
            let leaked = try await service.launch(request)
            XCTFail("Expected an invalid-callback failure, got \(leaked).")
        } catch let error as BrowserExtensionWebAuthenticationError {
            XCTAssertEqual(error, .invalidCallback)
        }
    }
}
