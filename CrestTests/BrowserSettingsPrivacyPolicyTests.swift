import XCTest

@testable import Crest

@MainActor
final class BrowserSettingsPrivacyPolicyTests: XCTestCase {
    func testLiveSpaceSelectionRejectsStaleSourcesAndUnavailableDestinationsWithoutMutation() {
        for invalidation in SettingsSelectionInvalidation.allCases {
            var session = BrowserSession.preview
            let settings = BrowserTab(title: "Settings", url: nil, nativeContent: .settings, placement: .current)
            // A tab that shows something else now, under the identity the
            // Settings tab had when the selection was captured.
            session.spaces[0].tabs.append(
                invalidation == .replacedTabContent
                    ? BrowserTab(
                        id: settings.id, title: "Getting Started", url: nil, nativeContent: .gettingStarted,
                        placement: .current)
                    : settings)
            let source = session.spaces[0]
            let destination = session.spaces[1]
            let browser = BrowserStore(session: session)
            browser.selectSpace(source.id)
            let action = BrowserSettingsSpaceSelectionAction(
                browser: browser, spaceAccess: BrowserSpaceAccessController())
            let assignment = BrowserTabRuntimeAssignment(
                tabID: settings.id, spaceID: source.id, profileID: source.profile.id)
            switch invalidation {
            case .removedTab:
                browser.deleteTab(settings.id, in: source.id)
            case .replacedTabContent:
                break
            case .replacedProfile:
                browser.replaceProfileForTesting(of: source.id)
            case .lockedSource:
                browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: source.id)
            case .unselectedSource:
                browser.selectPresentedSpace(destination.id)
            case .deletingSource:
                _ = browser.family.beginDeletingSpace(source.id)
            case .lockedDestination:
                browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: destination.id)
            case .deletingDestination:
                _ = browser.family.beginDeletingSpace(destination.id)
            case .missingDestination:
                browser.removeSpaceForTesting(destination.id)
            }
            let before = browser.session
            let revision = browser.sessionRevision

            XCTAssertNil(action.select(destination.id, matching: assignment), "\(invalidation)")

            XCTAssertEqual(browser.session, before, "\(invalidation)")
            XCTAssertEqual(browser.sessionRevision, revision, "\(invalidation)")
        }
    }

    func testPrivateSpaceSettingsStayProtectedUntilTheSpaceIsUnlocked() async throws {
        var session = BrowserSession.preview
        session.spaces[0].accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore(session: session)
        let space = browser.session.spaces[0]
        let access = BrowserSpaceAccessController(
            authenticator: SettingsPrivacyAuthenticatorStub(result: true)
        )
        browser.attachSpaceAccess(access)

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

    func testLockedSpacesForExportIncludesOnlyStillLockedPrivateSpaces() async throws {
        var session = BrowserSession.preview
        session.spaces[0].accessPolicy = .deviceOwnerAuthentication
        session.spaces[1].accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore(session: session)
        let spaces = browser.session.spaces
        let access = BrowserSpaceAccessController(
            authenticator: SettingsPrivacyAuthenticatorStub(result: true)
        )
        browser.attachSpaceAccess(access)

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
        browser.attachSpaceAccess(access)
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

}

private enum SettingsSelectionInvalidation: CaseIterable {
    case removedTab, replacedTabContent, replacedProfile, lockedSource, unselectedSource, deletingSource
    case lockedDestination, deletingDestination, missingDestination
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
