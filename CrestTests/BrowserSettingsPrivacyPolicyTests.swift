import XCTest

@testable import Crest

@MainActor
final class BrowserSettingsPrivacyPolicyTests: XCTestCase {
    func testLiveSpaceSelectionAcceptsAnUnfocusedSettingsSplitAndReusesTheDestinationTab() throws {
        var session = BrowserSession.preview
        let sourceIndex = 0
        let destinationIndex = 1
        let group = SplitGroupID()
        let sourcePage = BrowserTab(
            title: "Page", url: URL(string: "https://example.com"), placement: .current, splitGroupID: group)
        let sourceSettings = BrowserTab(
            title: "Settings", url: nil, nativeContent: .settings, placement: .current, splitGroupID: group)
        let destinationSettings = BrowserTab(title: "Settings", url: nil, nativeContent: .settings, placement: .current)
        session.spaces[sourceIndex].tabs.append(contentsOf: [sourcePage, sourceSettings])
        session.spaces[sourceIndex].selectedTabID = sourcePage.id
        session.spaces[destinationIndex].tabs.append(destinationSettings)
        let source = session.spaces[sourceIndex]
        let destination = session.spaces[destinationIndex]
        session.selectedSpaceID = source.id
        let persistence = InMemoryBrowserSessionPersistence()
        let browser = BrowserStore(session: session, persistence: persistence)
        let action = BrowserSettingsSpaceSelectionAction(browser: browser, spaceAccess: BrowserSpaceAccessController())
        let sourceAssignment = BrowserTabRuntimeAssignment(
            tabID: sourceSettings.id, spaceID: source.id, profileID: source.profile.id)
        XCTAssertNotEqual(browser.selectedTab?.id, sourceSettings.id)

        let selected = action.select(destination.id, matching: sourceAssignment)

        XCTAssertEqual(
            selected,
            BrowserTabRuntimeAssignment(
                tabID: destinationSettings.id, spaceID: destination.id, profileID: destination.profile.id))
        XCTAssertEqual(browser.session.selectedSpaceID, destination.id)
        XCTAssertEqual(browser.selectedTab?.id, destinationSettings.id)
        XCTAssertEqual(browser.selectedSpace?.tabs.filter { $0.nativeContent == .settings }.count, 1)
        XCTAssertEqual(browser.session.space(id: source.id), source)
        XCTAssertEqual(try XCTUnwrap(persistence.load()), browser.session)
    }

    func testLiveSpaceSelectionRejectsStaleSourcesAndUnavailableDestinationsWithoutMutation() {
        for invalidation in SettingsSelectionInvalidation.allCases {
            var session = BrowserSession.preview
            let settings = BrowserTab(title: "Settings", url: nil, nativeContent: .settings, placement: .current)
            session.spaces[0].tabs.append(settings)
            let source = session.spaces[0]
            let destination = session.spaces[1]
            session.selectedSpaceID = source.id
            let persistence = InMemoryBrowserSessionPersistence()
            let browser = BrowserStore(session: session, persistence: persistence)
            let action = BrowserSettingsSpaceSelectionAction(
                browser: browser, spaceAccess: BrowserSpaceAccessController())
            let assignment = BrowserTabRuntimeAssignment(
                tabID: settings.id, spaceID: source.id, profileID: source.profile.id)
            switch invalidation {
            case .removedTab:
                browser.session.spaces[0].tabs.removeAll { $0.id == settings.id }
            case .replacedTabContent:
                browser.session.spaces[0].tabs[browser.session.spaces[0].tabs.count - 1] = BrowserTab(
                    id: settings.id, title: "Getting Started", url: nil, nativeContent: .gettingStarted,
                    placement: .current)
            case .replacedProfile:
                browser.session.spaces[0] = BrowserSpace(
                    id: source.id, profile: BrowsingProfile(id: UUID()), name: source.name,
                    symbol: source.symbol, accent: source.accent, folders: source.folders,
                    tabs: source.tabs, selectedTabID: source.selectedTabID)
            case .lockedSource:
                browser.session.spaces[0].accessPolicy = .deviceOwnerAuthentication
            case .unselectedSource:
                browser.session.selectedSpaceID = destination.id
            case .deletingSource:
                _ = browser.family.beginDeletingSpace(source.id)
            case .lockedDestination:
                browser.session.spaces[1].accessPolicy = .deviceOwnerAuthentication
            case .deletingDestination:
                _ = browser.family.beginDeletingSpace(destination.id)
            case .missingDestination:
                browser.session.spaces.removeLast()
            }
            let before = browser.session
            let savedCount = persistence.savedScopes.count

            XCTAssertNil(action.select(destination.id, matching: assignment), "\(invalidation)")

            XCTAssertEqual(browser.session, before, "\(invalidation)")
            XCTAssertEqual(persistence.savedScopes.count, savedCount, "\(invalidation)")
        }
    }

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
