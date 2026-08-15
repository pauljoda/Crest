import XCTest

@testable import CrestMobile

@MainActor
final class BrowserSystemPasswordWriteThroughIsolationTests: XCTestCase {
    func testOrdinaryLaunchKeepsSystemPasswordWriteThroughAvailable() {
        XCTAssertEqual(
            BrowserSystemPasswordWriteThroughSystem.availability(
                for: BrowserLaunchEnvironment(
                    values: [:],
                    isXCTestRuntime: false
                )
            ),
            .available
        )
    }

    func testIsolatedLaunchRejectsWriteThroughBeforePresentation() async throws {
        let launchEnvironment = BrowserLaunchEnvironment(
            values: ["CREST_ISOLATED_SESSION": "1"],
            isXCTestRuntime: false
        )

        XCTAssertEqual(
            BrowserSystemPasswordWriteThroughSystem.availability(
                for: launchEnvironment
            ),
            .isolatedLaunch
        )

        do {
            try await BrowserSystemPasswordWriteThroughSystem.offer(
                candidate: try candidate(),
                title: "Isolated",
                anchor: nil,
                launchEnvironment: launchEnvironment
            )
            XCTFail("An isolated launch must not reach ASCredentialDataManager.")
        } catch {
            XCTAssertEqual(
                error as? BrowserSystemPasswordWriteThroughError,
                .unavailable
            )
        }
    }

    private func candidate() throws -> BrowserCredentialSaveCandidate {
        let origin = try XCTUnwrap(
            CredentialOrigin(
                url: try XCTUnwrap(
                    URL(string: "https://accounts.example.com")
                )
            )
        )
        return BrowserCredentialSaveCandidate(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000001"
            )!,
            origin: origin,
            topLevelOrigin: origin,
            username: "person@example.com",
            password: "secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
