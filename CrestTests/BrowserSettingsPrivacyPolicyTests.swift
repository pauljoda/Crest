import XCTest
@testable import Crest

@MainActor
final class BrowserSettingsPrivacyPolicyTests: XCTestCase {
    func testPrivateSpaceSettingsStayProtectedUntilTheSpaceIsUnlocked() async throws {
        var space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        space.accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(
            authenticator: SettingsPrivacyAuthenticatorStub(result: true)
        )

        XCTAssertFalse(
            BrowserSettingsPrivacyPolicy.canRevealSpaceData(
                in: space,
                accessController: access
            )
        )

        let unlocked = await access.unlock(space)

        XCTAssertTrue(unlocked)

        XCTAssertTrue(
            BrowserSettingsPrivacyPolicy.canRevealSpaceData(
                in: space,
                accessController: access
            )
        )
    }

    func testLockedSpacePickerSummaryDoesNotRevealTabCount() throws {
        var space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        space.accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(
            authenticator: SettingsPrivacyAuthenticatorStub(result: true)
        )

        let summary = BrowserSettingsPrivacyPolicy.spacePickerSummary(
            for: space,
            isDefault: true,
            accessController: access
        )

        XCTAssertTrue(summary.contains("Default"))
        XCTAssertTrue(summary.contains("Private"))
        XCTAssertFalse(summary.contains("tab"))
        XCTAssertFalse(summary.contains(space.tabs.count.formatted()))
    }

    func testLockedSpacesForExportIncludesOnlyStillLockedPrivateSpaces() async throws {
        var spaces = BrowserSession.preview.spaces
        spaces[0].accessPolicy = .deviceOwnerAuthentication
        spaces[1].accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(
            authenticator: SettingsPrivacyAuthenticatorStub(result: true)
        )

        let unlocked = await access.unlock(spaces[0])

        XCTAssertTrue(unlocked)

        XCTAssertEqual(
            BrowserSettingsPrivacyPolicy.lockedSpaces(
                in: spaces,
                accessController: access
            ).map(\.id),
            [spaces[1].id]
        )
    }

    func testCredentialMetadataLoadsOnlyWhilePrivateSpaceIsUnlocked() async throws {
        var session = BrowserSession.preview
        session.spaces[0].accessPolicy = .deviceOwnerAuthentication
        let space = session.spaces[0]
        let browser = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault()
        )
        let url = try XCTUnwrap(URL(string: "https://accounts.example.com/sign-in"))
        _ = try await browser.saveCredential(
            username: "private-user",
            password: "private-secret",
            for: url,
            in: space.id
        )
        let access = BrowserSpaceAccessController(
            authenticator: SettingsPrivacyAuthenticatorStub(result: true)
        )
        let credentials = BrowserCredentialSpaceStore(browser: browser)

        await credentials.load(in: space.id, accessController: access)

        XCTAssertTrue(credentials.descriptors.isEmpty)

        let unlocked = await access.unlock(space)

        XCTAssertTrue(unlocked)
        await credentials.load(in: space.id, accessController: access)

        XCTAssertEqual(credentials.descriptors.map(\.username), ["private-user"])

        access.lock(space.id)
        await credentials.load(in: space.id, accessController: access)

        XCTAssertTrue(credentials.descriptors.isEmpty)
    }

    func testLockedRouteDestinationsAreDeduplicatedInSpaceOrder() throws {
        var spaces = BrowserSession.preview.spaces
        spaces[0].accessPolicy = .deviceOwnerAuthentication
        spaces[1].accessPolicy = .deviceOwnerAuthentication
        let access = BrowserSpaceAccessController(
            authenticator: SettingsPrivacyAuthenticatorStub(result: true)
        )
        let routes = [
            BrowserLinkRoute(pattern: "private.example", destinationSpaceID: spaces[1].id),
            BrowserLinkRoute(pattern: "work.example", destinationSpaceID: spaces[0].id),
            BrowserLinkRoute(pattern: "private.example/path", destinationSpaceID: spaces[1].id),
        ]

        XCTAssertEqual(
            BrowserSettingsPrivacyPolicy.lockedRouteDestinationSpaces(
                for: routes,
                in: spaces,
                accessController: access
            ).map(\.id),
            [spaces[0].id, spaces[1].id]
        )
    }
}

@MainActor
private final class SettingsPrivacyAuthenticatorStub: BrowserDeviceAuthenticating {
    let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func authenticate(reason: String) async throws -> Bool {
        result
    }
}
