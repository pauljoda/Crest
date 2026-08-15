import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserRootModelTests: XCTestCase {
    func testSelectionChangeClassifiesRevisionTabSpaceAndProfileTransitions() {
        let firstSpaceID = SpaceID(rawValue: fixedUUID(1))
        let secondSpaceID = SpaceID(rawValue: fixedUUID(2))
        let firstProfileID = fixedUUID(3)
        let secondProfileID = fixedUUID(4)
        let firstTabID = TabID(rawValue: fixedUUID(5))
        let secondTabID = TabID(rawValue: fixedUUID(6))
        let original = selectionSnapshot(
            revision: 1,
            tabID: firstTabID,
            spaceID: firstSpaceID,
            profileID: firstProfileID
        )

        XCTAssertEqual(
            MobileBrowserRootSelectionChange.resolve(
                from: original,
                to: selectionSnapshot(
                    revision: 2,
                    tabID: firstTabID,
                    spaceID: firstSpaceID,
                    profileID: firstProfileID
                )
            ),
            .unchanged
        )
        XCTAssertEqual(
            MobileBrowserRootSelectionChange.resolve(
                from: original,
                to: selectionSnapshot(
                    revision: 2,
                    tabID: secondTabID,
                    spaceID: firstSpaceID,
                    profileID: firstProfileID
                )
            ),
            .tab
        )
        XCTAssertEqual(
            MobileBrowserRootSelectionChange.resolve(
                from: original,
                to: selectionSnapshot(
                    revision: 2,
                    tabID: secondTabID,
                    spaceID: secondSpaceID,
                    profileID: secondProfileID
                )
            ),
            .space
        )
        XCTAssertEqual(
            MobileBrowserRootSelectionChange.resolve(
                from: original,
                to: selectionSnapshot(
                    revision: 2,
                    tabID: firstTabID,
                    spaceID: firstSpaceID,
                    profileID: secondProfileID
                )
            ),
            .profile
        )
    }

    func testSelectionSynchronizationNeverCrossesSpaceOrProfileOwnership() async throws {
        let firstSpace = makeSpace(index: 10)
        let secondSpace = makeSpace(index: 20)
        let fixture = makeFixture(
            spaces: [firstSpace, secondSpace],
            selectedSpaceID: firstSpace.id,
            startupBehavior: .lastActiveTab
        )
        fixture.model.presentationChanged(to: .regular)
        await fixture.model.prepareBrowser()

        XCTAssertEqual(fixture.pages.activePage?.spaceID, firstSpace.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, firstSpace.profile.id)

        let beforeSpaceChange = fixture.model.selectionSnapshot
        fixture.browser.selectSpace(secondSpace.id)
        let afterSpaceChange = fixture.model.selectionSnapshot
        XCTAssertTrue(
            fixture.model.synchronizeSelection(
                from: beforeSpaceChange,
                to: afterSpaceChange
            )
        )
        XCTAssertEqual(fixture.pages.activePage?.spaceID, secondSpace.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, secondSpace.profile.id)
        XCTAssertTrue(
            fixture.pages.containsResidentPage(
                for: try XCTUnwrap(firstSpace.selectedTabID)
            )
        )
    }

    func testProfileRevisionBeforePreparationUsesOnlyTheCurrentProfile() async throws {
        let originalSpace = makeSpace(index: 22)
        let fixture = makeFixture(
            spaces: [originalSpace],
            selectedSpaceID: originalSpace.id,
            startupBehavior: .lastActiveTab
        )
        fixture.model.presentationChanged(to: .regular)
        let replacementProfile = BrowsingProfile(id: fixedUUID(99))
        let beforeProfileChange = fixture.model.selectionSnapshot
        var session = fixture.browser.session
        session.spaces[0] = replacingProfile(
            of: originalSpace,
            with: replacementProfile
        )
        fixture.browser.session = session
        let afterProfileChange = fixture.model.selectionSnapshot

        XCTAssertEqual(
            MobileBrowserRootSelectionChange.resolve(
                from: beforeProfileChange,
                to: afterProfileChange
            ),
            .profile
        )
        XCTAssertFalse(
            fixture.model.synchronizeSelection(
                from: beforeProfileChange,
                to: afterProfileChange
            )
        )
        XCTAssertNil(fixture.pages.activePage)

        await fixture.model.prepareBrowser()

        XCTAssertEqual(fixture.pages.activePage?.spaceID, originalSpace.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, replacementProfile.id)
    }

    func testSelectionWaitsForLifecyclePreparationThenActivatesTheCurrentAssignment()
        async throws
    {
        var space = makeSpace(index: 25)
        let deferredTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(254)),
            title: "Deferred",
            url: URL(string: "https://example.com/deferred"),
            placement: .current
        )
        space.tabs.append(deferredTab)
        let fixture = makeFixture(
            spaces: [space],
            selectedSpaceID: space.id,
            startupBehavior: .lastActiveTab
        )
        fixture.model.presentationChanged(to: .regular)

        let beforeSelection = fixture.model.selectionSnapshot
        fixture.browser.selectTab(deferredTab.id)
        let afterSelection = fixture.model.selectionSnapshot

        XCTAssertFalse(
            fixture.model.synchronizeSelection(
                from: beforeSelection,
                to: afterSelection
            )
        )
        XCTAssertNil(fixture.pages.activePage)
        XCTAssertFalse(fixture.model.hasPreparedBrowser)

        await fixture.model.prepareBrowser()

        XCTAssertTrue(fixture.model.hasPreparedBrowser)
        XCTAssertEqual(fixture.pages.activePage?.tabID, deferredTab.id)
        XCTAssertEqual(fixture.pages.activePage?.spaceID, space.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, space.profile.id)
    }

    func testCommandSelectionDismissesPresentationBeforeSynchronizingAddress()
        async throws
    {
        var space = makeSpace(index: 27)
        let destinationURL = try XCTUnwrap(
            URL(string: "https://example.com/command-destination")
        )
        let destinationTab = BrowserTab(
            id: TabID(rawValue: fixedUUID(274)),
            title: "Command destination",
            url: destinationURL,
            placement: .current
        )
        space.tabs.append(destinationTab)
        let fixture = makeFixture(
            spaces: [space],
            selectedSpaceID: space.id,
            startupBehavior: .lastActiveTab
        )
        fixture.model.presentationChanged(to: .regular)
        await fixture.model.prepareBrowser()
        var addressBeforeSynchronization: String?
        var selectedTabBeforeSynchronization: TabID?

        let selected = fixture.model.selectNextTabFromCommand {
            addressBeforeSynchronization = fixture.model.address
            selectedTabBeforeSynchronization = fixture.browser.selectedTab?.id
        }

        XCTAssertTrue(selected)
        XCTAssertEqual(selectedTabBeforeSynchronization, destinationTab.id)
        XCTAssertEqual(addressBeforeSynchronization, "")
        XCTAssertEqual(fixture.model.address, destinationURL.absoluteString)
        XCTAssertEqual(fixture.pages.activePage?.tabID, destinationTab.id)
    }

    func testCompactAndRegularStartupPreserveSelectedPageResidency() async throws {
        let space = makeSpace(index: 30)
        let fixture = makeFixture(
            spaces: [space],
            selectedSpaceID: space.id,
            startupBehavior: .lastActiveTab
        )

        fixture.model.presentationChanged(to: .regular)
        await fixture.model.prepareBrowser()
        let activePage = try XCTUnwrap(fixture.pages.activePage)
        XCTAssertEqual(activePage.spaceID, space.id)
        XCTAssertFalse(fixture.navigation.defersPageActivation)

        fixture.model.presentationChanged(to: .compact)
        fixture.navigation.showTabViewer()
        XCTAssertTrue(fixture.navigation.defersPageActivation)
        XCTAssertTrue(fixture.pages.containsResidentPage(for: activePage.tabID))

        fixture.model.activateSelectedTab()
        XCTAssertTrue(try XCTUnwrap(fixture.pages.activePage) === activePage)
        XCTAssertTrue(fixture.navigation.compactShowsPage)
    }

    func testPrivateCompactStartupWaitsForSelectionAndUsesItsEphemeralProfile() async throws {
        let space = makeSpace(index: 40)
        let fixture = makeFixture(
            spaces: [space],
            selectedSpaceID: space.id,
            browsingMode: .privateBrowsing,
            startupBehavior: .waitForTabSelection
        )
        fixture.model.presentationChanged(to: .compact)

        await fixture.model.prepareBrowser()

        XCTAssertNil(fixture.pages.activePage)
        XCTAssertTrue(fixture.navigation.defersPageActivation)

        fixture.model.activateSelectedTab()
        let page = try XCTUnwrap(fixture.pages.activePage)
        XCTAssertEqual(page.spaceID, space.id)
        XCTAssertEqual(page.profileID, space.profile.id)
        XCTAssertFalse(page.webView.configuration.websiteDataStore.isPersistent)
    }

    func testUnlockDestinationKeepsCompactInViewerAndActivatesRegularPage() async throws {
        var protectedSpace = makeSpace(index: 50)
        protectedSpace.accessPolicy = .deviceOwnerAuthentication
        let authenticator = MobileRootDeviceAuthenticator()
        let access = BrowserSpaceAccessController(authenticator: authenticator)
        let fixture = makeFixture(
            spaces: [protectedSpace],
            selectedSpaceID: protectedSpace.id,
            startupBehavior: .lastActiveTab,
            spaceAccess: access
        )
        fixture.model.presentationChanged(to: .compact)
        await fixture.model.prepareBrowser()
        let lockedCompact = fixture.model.lockSnapshot(presentation: .compact)
        fixture.model.synchronizeLockTransition(
            from: lockedCompact,
            to: lockedCompact
        )
        XCTAssertNil(fixture.pages.activePage)

        let compactUnlockSucceeded = await access.unlock(protectedSpace)
        XCTAssertTrue(compactUnlockSucceeded)
        let unlockedCompact = fixture.model.lockSnapshot(presentation: .compact)
        fixture.model.synchronizeLockTransition(
            from: lockedCompact,
            to: unlockedCompact
        )
        XCTAssertNil(fixture.pages.activePage)
        XCTAssertFalse(fixture.navigation.compactShowsPage)

        access.lock(protectedSpace.id)
        fixture.model.presentationChanged(to: .regular)
        let lockedRegular = fixture.model.lockSnapshot(presentation: .regular)
        fixture.model.synchronizeLockTransition(
            from: unlockedCompact,
            to: lockedRegular
        )
        XCTAssertNil(fixture.pages.activePage)

        let regularUnlockSucceeded = await access.unlock(protectedSpace)
        XCTAssertTrue(regularUnlockSucceeded)
        let unlockedRegular = fixture.model.lockSnapshot(presentation: .regular)
        fixture.model.synchronizeLockTransition(
            from: lockedRegular,
            to: unlockedRegular
        )
        XCTAssertEqual(fixture.pages.activePage?.spaceID, protectedSpace.id)
        XCTAssertEqual(fixture.pages.activePage?.profileID, protectedSpace.profile.id)
    }

    func testPaletteActionsRejectStaleProfilesAndSelectExactDestinations() throws {
        let source = makeSpace(index: 60)
        let destination = makeSpace(index: 70)
        let fixture = makeFixture(
            spaces: [source, destination],
            selectedSpaceID: source.id,
            startupBehavior: .waitForTabSelection
        )
        let sourceAssignment = BrowserTabRuntimeAssignment(
            tabID: try XCTUnwrap(source.selectedTabID),
            spaceID: source.id,
            profileID: source.profile.id
        )
        let destinationAssignment = BrowserTabRuntimeAssignment(
            tabID: try XCTUnwrap(destination.selectedTabID),
            spaceID: destination.id,
            profileID: destination.profile.id
        )

        XCTAssertTrue(
            fixture.model.selectPaletteTab(
                from: sourceAssignment,
                to: destinationAssignment
            )
        )
        XCTAssertEqual(fixture.browser.selectedSpace?.id, destination.id)
        XCTAssertEqual(fixture.browser.selectedSpace?.profile.id, destination.profile.id)
        XCTAssertEqual(fixture.browser.selectedTab?.id, destinationAssignment.tabID)
        XCTAssertEqual(fixture.pages.activePage?.profileID, destination.profile.id)

        let replacement = replacingProfile(
            of: source,
            with: BrowsingProfile(id: fixedUUID(0xFE))
        )
        fixture.browser.session = BrowserSession(
            spaces: [replacement, destination],
            selectedSpaceID: replacement.id
        )
        let replacementURL = fixture.browser.selectedTab?.url

        XCTAssertFalse(
            fixture.model.openPaletteURL(
                URL(fileURLWithPath: "/stale-palette-navigation"),
                mode: .editLocation(""),
                from: sourceAssignment
            )
        )
        XCTAssertEqual(fixture.browser.selectedTab?.url, replacementURL)
        XCTAssertFalse(
            fixture.model.selectPaletteTab(
                from: sourceAssignment,
                to: destinationAssignment
            )
        )
        XCTAssertEqual(fixture.browser.selectedSpace?.profile.id, replacement.profile.id)
    }

    private func makeFixture(
        spaces: [BrowserSpace],
        selectedSpaceID: SpaceID,
        browsingMode: BrowserBrowsingMode = .standard,
        startupBehavior: BrowserStartupBehavior,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController()
    ) -> MobileBrowserRootFixture {
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: browsingMode
        )
        let pages = MobileBrowserPageStore(
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: true,
            contentRuleListProvider: EmptyMobileRootContentRuleListProvider()
        )
        let navigation = MobileBrowserNavigationState()
        let model = MobileBrowserRootModel(
            browser: browser,
            pages: pages,
            navigation: navigation,
            spaceAccess: spaceAccess,
            windowState: nil,
            startupBehavior: startupBehavior,
            persistedSidebarWidth: MobileBrowserRootLayout.defaultRegularSidebarWidth
        )
        return MobileBrowserRootFixture(
            browser: browser,
            pages: pages,
            navigation: navigation,
            model: model
        )
    }

    private func makeSpace(index: Int) -> BrowserSpace {
        let tab = BrowserTab.startPage(
            id: TabID(rawValue: fixedUUID(index * 10 + 1)),
            placement: .current
        )
        return BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(index * 10 + 2)),
            profile: BrowsingProfile(id: fixedUUID(index * 10 + 3)),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    private func replacingProfile(
        of space: BrowserSpace,
        with profile: BrowsingProfile
    ) -> BrowserSpace {
        BrowserSpace(
            id: space.id,
            profile: profile,
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            branding: space.branding,
            folders: space.folders,
            tabs: space.tabs,
            archivedTabs: space.archivedTabs,
            history: space.history,
            browsingPreferences: space.browsingPreferences,
            credentialPreferences: space.credentialPreferences,
            accessPolicy: space.accessPolicy,
            isSavedTabsExpanded: space.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: space.savedTabsExpansionModifiedAt,
            selectedTabID: space.selectedTabID
        )
    }

    private func selectionSnapshot(
        revision: Int,
        tabID: TabID,
        spaceID: SpaceID,
        profileID: UUID
    ) -> MobileBrowserRootSelectionSnapshot {
        MobileBrowserRootSelectionSnapshot(
            sessionRevision: revision,
            selectedSpaceID: spaceID,
            selectedProfileID: profileID,
            assignment: BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: spaceID,
                profileID: profileID
            )
        )
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012x",
                value
            )
        )!
    }
}

@MainActor
private struct MobileBrowserRootFixture {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let model: MobileBrowserRootModel
}

@MainActor
private final class EmptyMobileRootContentRuleListProvider:
    BrowserContentRuleListProviding
{
    func balancedRuleLists() async throws -> [WKContentRuleList] { [] }
}

@MainActor
private final class MobileRootDeviceAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason: String) async throws -> Bool { true }
}
