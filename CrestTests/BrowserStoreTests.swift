import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserStoreTests: XCTestCase {
    func testClosingANewSearchReturnsToTheTabThatWasActuallyOpen() throws {
        let mediaLibrary = BrowserTab(
            title: "Media Library",
            url: URL(string: "https://media.example"),
            placement: .pinned,
            lastActivatedAt: Date(timeIntervalSince1970: 100)
        )
        let lidarr = BrowserTab(
            title: "Lidarr",
            url: URL(string: "https://lidarr.example"),
            placement: .saved,
            lastActivatedAt: Date(timeIntervalSince1970: 200)
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [mediaLibrary, lidarr],
            selectedTabID: mediaLibrary.id
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let searchID = try XCTUnwrap(
            store.openNewTab(
                url: try XCTUnwrap(URL(string: "https://www.google.com/search?q=testing"))
            )
        )

        store.closeTab(searchID)

        XCTAssertEqual(store.selectedTab?.id, mediaLibrary.id)
    }

    func testClosingTheActiveTabShowsTheUnloadedStateWhenItsHistoryIsGone() throws {
        let mediaLibrary = BrowserTab(
            title: "Media Library",
            url: URL(string: "https://media.example"),
            placement: .pinned,
            lastActivatedAt: Date(timeIntervalSince1970: 100)
        )
        let lidarr = BrowserTab(
            title: "Lidarr",
            url: URL(string: "https://lidarr.example"),
            placement: .saved,
            lastActivatedAt: Date(timeIntervalSince1970: 200)
        )
        let sonarr = BrowserTab(
            title: "Sonarr",
            url: URL(string: "https://sonarr.example"),
            placement: .saved,
            lastActivatedAt: Date(timeIntervalSince1970: 50)
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [mediaLibrary, lidarr, sonarr],
            selectedTabID: mediaLibrary.id
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        store.selectTab(sonarr.id)
        store.selectTab(mediaLibrary.id)
        let searchID = try XCTUnwrap(
            store.openNewTab(
                url: try XCTUnwrap(URL(string: "https://www.google.com/search?q=testing"))
            )
        )
        store.deleteTab(mediaLibrary.id, in: space.id)

        store.closeTab(searchID)

        XCTAssertNil(store.selectedTab)
        XCTAssertEqual(Set(store.selectedSpace?.tabs.map(\.id) ?? []), [lidarr.id, sonarr.id])
    }

    func testSuccessiveClosesWalkBackThroughActualTabActivationHistory() throws {
        let first = BrowserTab(
            title: "First",
            url: URL(string: "https://first.example"),
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [first],
            selectedTabID: first.id
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let secondID = try XCTUnwrap(
            store.openNewTab(url: try XCTUnwrap(URL(string: "https://second.example")))
        )
        let thirdID = try XCTUnwrap(
            store.openNewTab(url: try XCTUnwrap(URL(string: "https://third.example")))
        )

        store.closeTab(thirdID)
        XCTAssertEqual(store.selectedTab?.id, secondID)

        store.closeTab(secondID)
        XCTAssertEqual(store.selectedTab?.id, first.id)
    }

    func testSessionRevisionAdvancesWhenTheStoreMutatesSessionState() {
        let store = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence()
        )
        let initialRevision = store.sessionRevision

        _ = store.openNewTab()

        XCTAssertGreaterThan(store.sessionRevision, initialRevision)
    }

    func testRuntimeProjectionMatchesTheSpecializedSessionSnapshots() {
        let session = BrowserSession.preview
        let projection = BrowserRuntimeSessionProjection(session: session)

        XCTAssertEqual(
            projection.extensionState,
            BrowserExtensionSessionState(session: session)
        )
        XCTAssertEqual(
            projection.tabIconState,
            BrowserTabIconSessionState(session: session)
        )
        XCTAssertEqual(
            projection.contentBlockingState,
            BrowserContentBlockingSessionState(session: session)
        )
        XCTAssertEqual(
            projection.credentialAccessState,
            Dictionary(
                uniqueKeysWithValues: session.spaces.map {
                    ($0.id, $0.credentialPreferences.isEnabled)
                }
            )
        )
    }

    func testFreshInstallSeedPersistsButNeverStagesBeforeCloudBootstrap() async throws {
        let sessionPersistence = InMemoryBrowserSessionPersistence()
        let syncPersistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: syncPersistence,
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        )
        let store = BrowserStore(
            session: .freshInstallSeed,
            persistence: sessionPersistence,
            syncCoordinator: coordinator,
            syncCoalescingDelay: .zero
        )

        store.openNewTab(
            url: try XCTUnwrap(URL(string: "https://example.com/before-first-sync"))
        )
        await store.flushPendingSyncPersistence()
        let outboundRecords = await store.cloudSyncRecords()
        let outboundPendingRecordIDs = await store.cloudSyncPendingRecordIDs()

        XCTAssertTrue(store.session.hasDisposableSeedState)
        XCTAssertTrue(try XCTUnwrap(sessionPersistence.session).hasDisposableSeedState)
        let encoded = try JSONEncoder().encode(store.session)
        XCTAssertTrue(try JSONDecoder().decode(BrowserSession.self, from: encoded).hasDisposableSeedState)
        XCTAssertTrue(coordinator.journal.records.isEmpty)
        XCTAssertTrue(coordinator.journal.pendingRecordIDs.isEmpty)
        XCTAssertTrue(outboundRecords.isEmpty)
        XCTAssertTrue(outboundPendingRecordIDs.isEmpty)
        XCTAssertEqual(store.pendingSyncRecordCount, 0)
    }

    func testFirstCloudBootstrapReplacesDisposableSeedInsteadOfMergingIt() throws {
        let cloudSession = BrowserSession.privateBrowsing()
        let cloudCoordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000098")!
        )
        try cloudCoordinator.stage(session: cloudSession)
        try cloudCoordinator.markUploaded(cloudCoordinator.journal.pendingRecordIDs)
        let cloudRecords = cloudCoordinator.journal.records

        let localCoordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000097")!
        )
        let store = BrowserStore(
            session: .freshInstallSeed,
            persistence: InMemoryBrowserSessionPersistence(),
            syncCoordinator: localCoordinator
        )
        let seededSpaceIDs = Set(store.session.spaces.map(\.id))

        try store.replaceDisposableSeedWithCloud(cloudRecords)

        XCTAssertFalse(store.session.hasDisposableSeedState)
        XCTAssertEqual(store.session.spaces.map(\.id), cloudSession.spaces.map(\.id))
        XCTAssertTrue(seededSpaceIDs.isDisjoint(with: store.session.spaces.map(\.id)))
        XCTAssertEqual(localCoordinator.journal.records, cloudRecords)
        XCTAssertTrue(localCoordinator.journal.pendingRecordIDs.isEmpty)
    }

    func testFirstCloudBootstrapClearsDisposableSeedWhenCloudIsEmpty() throws {
        let coordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000096")!
        )
        let store = BrowserStore(
            session: .freshInstallSeed,
            persistence: InMemoryBrowserSessionPersistence(),
            syncCoordinator: coordinator
        )
        let seededSpaceIDs = Set(store.session.spaces.map(\.id))

        try store.replaceDisposableSeedWithCloud([])

        XCTAssertFalse(store.session.hasDisposableSeedState)
        XCTAssertEqual(store.session.spaces.count, 1)
        XCTAssertEqual(store.selectedSpace?.name, "Space 1")
        XCTAssertTrue(seededSpaceIDs.isDisjoint(with: store.session.spaces.map(\.id)))
        XCTAssertTrue(coordinator.journal.records.isEmpty)
        XCTAssertTrue(coordinator.journal.pendingRecordIDs.isEmpty)
    }

    func testPrivateBrowsingIsEphemeralAndCannotUseCrestPasswords() async throws {
        let store = BrowserStore.privateBrowsing()
        let originalSpaceID = store.session.selectedSpaceID
        let originalProfileID = try XCTUnwrap(store.selectedSpace?.profile.id)
        let originalTabID = try XCTUnwrap(store.selectedTab?.id)
        let url = try XCTUnwrap(URL(string: "https://private.crest.test/account"))

        XCTAssertTrue(store.isPrivateBrowsing)
        XCTAssertNil(store.syncCoordinator)
        XCTAssertEqual(store.selectedSpace?.name, "Private")
        XCTAssertEqual(store.selectedSpace?.symbol, "eyeglasses")
        XCTAssertEqual(
            store.selectedSpace?.branding.colors,
            [
                BrowserSpaceBrandColor(
                    red: 0.58,
                    green: 0.30,
                    blue: 0.76
                )
            ]
        )
        XCTAssertEqual(store.selectedSpace?.branding.bannerPattern, .solid)
        XCTAssertEqual(store.selectedSpace?.browsingPreferences.searchProvider, .duckDuckGo)
        XCTAssertEqual(store.selectedSpace?.browsingPreferences.currentTabCleanupPolicy, .never)
        XCTAssertFalse(
            try XCTUnwrap(store.selectedSpace)
                .credentialPreferences.syncsCrestPasswordsWithICloud
        )
        let privateSuggestions = try await store.credentialSuggestions(for: url)
        XCTAssertTrue(privateSuggestions.isEmpty)

        do {
            _ = try await store.saveCredential(
                username: "private-user",
                password: "private-secret",
                for: url
            )
            XCTFail("Private browsing must not save a Crest Password")
        } catch {
            XCTAssertEqual(
                error as? CredentialVaultError,
                .unavailableInPrivateBrowsing
            )
        }

        store.openNewTab(url: url)
        store.recordVisit(url: url, title: "Private account")
        XCTAssertFalse(try XCTUnwrap(store.selectedSpace).history.isEmpty)
        XCTAssertNotEqual(store.selectedTab?.id, originalTabID)

        store.resetPrivateBrowsingSession()

        XCTAssertNotEqual(store.session.selectedSpaceID, originalSpaceID)
        XCTAssertNotEqual(store.selectedSpace?.profile.id, originalProfileID)
        XCTAssertNotEqual(store.selectedTab?.id, originalTabID)
        XCTAssertEqual(store.session.spaces.count, 1)
        XCTAssertEqual(store.selectedSpace?.tabs.count, 1)
        XCTAssertTrue(try XCTUnwrap(store.selectedTab).isStartPage)
        XCTAssertTrue(try XCTUnwrap(store.selectedSpace).history.isEmpty)
        XCTAssertTrue(try XCTUnwrap(store.selectedSpace).archivedTabs.isEmpty)
    }

    func testEverySpaceAddedToAPrivateWindowKeepsThePrivateAppearance() throws {
        let store = BrowserStore.privateBrowsing()

        store.addSpace()

        XCTAssertEqual(store.session.spaces.count, 2)
        for space in store.session.spaces {
            XCTAssertEqual(space.symbol, "eyeglasses")
            XCTAssertEqual(space.branding.colors.count, 1)
            XCTAssertEqual(space.branding.bannerPattern, .solid)
        }
    }

    func testOpeningAURLCreatesAndSelectsACurrentTabInTheActiveSpace() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let spaceID = store.session.selectedSpaceID
        let originalCount = try XCTUnwrap(store.selectedSpace).currentTabs.count
        let url = try XCTUnwrap(URL(string: "https://example.com/popup"))

        store.openNewTab(url: url)

        XCTAssertEqual(store.session.selectedSpaceID, spaceID)
        XCTAssertEqual(try XCTUnwrap(store.selectedSpace).currentTabs.count, originalCount + 1)
        XCTAssertEqual(store.selectedTab?.url, url)
        XCTAssertEqual(store.selectedTab?.title, "example.com")
        XCTAssertEqual(persistence.session, store.session)
    }

    func testOpeningABackgroundTabPreservesSelectionAndUsesTheExactOwningSpace() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let selectedSpaceID = store.session.selectedSpaceID
        let selectedTabID = try XCTUnwrap(store.selectedTab?.id)
        let targetSpace = try XCTUnwrap(
            store.session.spaces.first { $0.id != selectedSpaceID }
        )
        let targetSelectedTabID = targetSpace.selectedTabID
        let targetCount = targetSpace.tabs.count
        let url = try XCTUnwrap(URL(string: "https://example.com/background"))

        let openedID = try XCTUnwrap(
            store.openNewTab(
                url: url,
                in: targetSpace.id,
                selecting: false
            )
        )

        XCTAssertEqual(store.session.selectedSpaceID, selectedSpaceID)
        XCTAssertEqual(store.selectedTab?.id, selectedTabID)
        XCTAssertEqual(store.session.space(id: targetSpace.id)?.selectedTabID, targetSelectedTabID)
        XCTAssertEqual(store.session.space(id: targetSpace.id)?.tabs.count, targetCount + 1)
        XCTAssertEqual(
            store.session.space(id: targetSpace.id)?.tabs.first { $0.id == openedID }?.url,
            url
        )
        XCTAssertEqual(
            store.session.space(id: targetSpace.id)?.tabs.first { $0.id == openedID }?.placement,
            .current
        )
        XCTAssertEqual(persistence.session, store.session)
    }

    func testOpeningNewTabReusesTheSpacesUncommittedStartPageDraft() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let draft = try XCTUnwrap(store.selectedSpace?.currentTabs.first(where: \.isStartPage))
        let originalCount = try XCTUnwrap(store.selectedSpace).currentTabs.count

        let openedID = store.openNewTab()

        XCTAssertEqual(openedID, draft.id)
        XCTAssertEqual(store.selectedTab?.id, draft.id)
        XCTAssertEqual(try XCTUnwrap(store.selectedSpace).currentTabs.count, originalCount)
        XCTAssertEqual(persistence.session, store.session)
    }

    func testTransientNilPageURLDoesNotEraseTheSelectedTabsCommittedURL() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let tab = try XCTUnwrap(store.selectedSpace?.tabs.first { $0.url != nil })
        store.selectTab(tab.id)

        store.updateSelectedTabFromPage(url: nil, title: "")

        XCTAssertEqual(store.selectedTab?.url, tab.url)
        XCTAssertEqual(persistence.session?.selectedTab?.url, tab.url)
    }

    func testNonNilPageURLStillUpdatesTheSelectedTab() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let url = try XCTUnwrap(URL(string: "https://example.com/committed"))

        store.updateSelectedTabFromPage(url: url, title: "Committed")

        XCTAssertEqual(store.selectedTab?.url, url)
        XCTAssertEqual(store.selectedTab?.title, "Committed")
        XCTAssertEqual(persistence.session, store.session)
    }

    /// An unfocused Split View card browses on its own, and its sidebar row has to
    /// follow it. Nothing about the selected tab may move while it does.
    func testAnUnfocusedCardUpdatesItsOwnTabAndLeavesTheSelectionAlone() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let space = try XCTUnwrap(store.selectedSpace)
        let selectedTab = try XCTUnwrap(store.selectedTab)
        let member = try XCTUnwrap(space.tabs.first { $0.id != selectedTab.id })
        let url = try XCTUnwrap(URL(string: "https://example.com/card"))

        XCTAssertTrue(
            store.updateTabFromPage(
                url: url,
                title: "Unfocused card",
                for: member.id,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        )

        let updated = try XCTUnwrap(
            store.selectedSpace?.tabs.first { $0.id == member.id }
        )
        XCTAssertEqual(updated.url, url)
        XCTAssertEqual(updated.title, "Unfocused card")
        XCTAssertEqual(store.selectedTab?.id, selectedTab.id)
        XCTAssertEqual(store.selectedTab?.url, selectedTab.url)
        XCTAssertEqual(store.selectedTab?.title, selectedTab.title)
        XCTAssertEqual(persistence.session, store.session)
    }

    /// The same gate the selected-tab path applies: a page that rewrites its title
    /// to the value already stored must not persist the session again.
    func testAnUnchangedCardPageWritesNothing() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let space = try XCTUnwrap(store.selectedSpace)
        let member = try XCTUnwrap(space.tabs.first { $0.url != nil })
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let saveCountBefore = persistence.savedScopes.count

        XCTAssertFalse(
            store.updateTabFromPage(
                url: member.url,
                title: member.title,
                for: member.id,
                matching: assignment
            )
        )
        XCTAssertEqual(persistence.savedScopes.count, saveCountBefore)
    }

    /// Mirrors `testTransientNilPageURLDoesNotEraseTheSelectedTabsCommittedURL`:
    /// a card whose page reports no URL yet keeps the URL the tab already has.
    func testATransientNilCardURLDoesNotEraseThatTabsCommittedURL() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let space = try XCTUnwrap(store.selectedSpace)
        let member = try XCTUnwrap(space.tabs.first { $0.url != nil })

        XCTAssertTrue(
            store.updateTabFromPage(
                url: nil,
                title: "Still loading",
                for: member.id,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        )

        let updated = try XCTUnwrap(
            store.selectedSpace?.tabs.first { $0.id == member.id }
        )
        XCTAssertEqual(updated.url, member.url)
        XCTAssertEqual(updated.title, "Still loading")
    }

    /// A card can hold a stale assignment for a frame after a Space switch or a
    /// profile rebuild. Writing across that boundary is the isolation failure
    /// per-Space browsing exists to prevent, so the write is simply refused.
    func testACardHoldingAStaleAssignmentWritesNothing() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let space = try XCTUnwrap(store.selectedSpace)
        let member = try XCTUnwrap(space.tabs.first { $0.url != nil })
        let url = try XCTUnwrap(URL(string: "https://example.com/other-profile"))

        XCTAssertFalse(
            store.updateTabFromPage(
                url: url,
                title: "Foreign profile",
                for: member.id,
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: space.id,
                    profileID: UUID()
                )
            )
        )
        XCTAssertFalse(
            store.updateTabFromPage(
                url: url,
                title: "Foreign Space",
                for: member.id,
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: SpaceID(),
                    profileID: space.profile.id
                )
            )
        )

        let unchanged = try XCTUnwrap(
            store.selectedSpace?.tabs.first { $0.id == member.id }
        )
        XCTAssertEqual(unchanged.url, member.url)
        XCTAssertEqual(unchanged.title, member.title)
    }

    /// A tab that is not in the Space is not a card of it.
    func testAnUnknownTabIDIsRefused() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let space = try XCTUnwrap(store.selectedSpace)

        XCTAssertFalse(
            store.updateTabFromPage(
                url: try XCTUnwrap(URL(string: "https://example.com/ghost")),
                title: "Ghost",
                for: TabID(),
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        )
    }

    /// The automatic-icon identity rules are the selected tab's rules: a renamed
    /// or emoji-iconed tab keeps the icon someone chose, whatever its page reports.
    func testACardNeverOverwritesAnIconSomeoneChose() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let space = try XCTUnwrap(store.selectedSpace)
        let member = try XCTUnwrap(space.tabs.first { $0.url != nil })
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        store.setTabEmojiIcon("🛰️", for: member.id, in: space.id)

        XCTAssertTrue(
            store.updateTabFromPage(
                url: try XCTUnwrap(URL(string: "https://example.com/settled")),
                title: "Settled",
                faviconData: Data("pulled".utf8),
                iconAccent: BrowserTabIconAccent(red: 0.1, green: 0.2, blue: 0.3),
                for: member.id,
                matching: assignment
            )
        )

        let updated = try XCTUnwrap(
            store.selectedSpace?.tabs.first { $0.id == member.id }
        )
        XCTAssertEqual(updated.iconMode, .emoji)
        XCTAssertNil(updated.faviconData)
        XCTAssertEqual(updated.title, "Settled")
    }

    func testUpdatingSpaceBrowsingPreferencesPersistsOnlyThatSpacesChoices() async throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let syncPersistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: syncPersistence,
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        )
        try coordinator.stage(session: .preview)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let store = BrowserStore(
            session: .preview,
            persistence: persistence,
            syncCoordinator: coordinator,
            syncCoalescingDelay: .zero
        )
        let selectedSpaceID = store.session.selectedSpaceID
        let otherSpace = try XCTUnwrap(
            store.session.spaces.first { $0.id != selectedSpaceID }
        )
        let preferences = BrowserSpaceBrowsingPreferences(
            searchProvider: .duckDuckGo,
            currentTabCleanupPolicy: .never
        )

        store.updateBrowsingPreferences(preferences, in: selectedSpaceID)
        await store.flushPendingSyncPersistence()

        XCTAssertEqual(
            store.session.space(id: selectedSpaceID)?.browsingPreferences,
            preferences
        )
        XCTAssertEqual(
            store.session.space(id: otherSpace.id)?.browsingPreferences,
            .default
        )
        XCTAssertEqual(persistence.session, store.session)
        let recordID = BrowserSyncRecordID(
            kind: .space,
            value: selectedSpaceID.rawValue
        )
        XCTAssertTrue(coordinator.journal.pendingRecordIDs.contains(recordID))
    }

    func testNormalStoreMutationStagesAndPersistsTheLocalSyncJournal() async throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let syncPersistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: syncPersistence,
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        try coordinator.stage(session: .preview)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let store = BrowserStore(
            session: .preview,
            persistence: persistence,
            syncCoordinator: coordinator,
            syncCoalescingDelay: .zero
        )

        store.openNewTab(url: try XCTUnwrap(URL(string: "https://example.com/synced")))
        await store.flushPendingSyncPersistence()

        let selectedID = try XCTUnwrap(store.selectedTab?.id)
        XCTAssertTrue(
            coordinator.journal.pendingRecordIDs.contains(
                BrowserSyncRecordID(kind: .tab, value: selectedID.rawValue)
            ))
        XCTAssertEqual(syncPersistence.journal, coordinator.journal)
        XCTAssertEqual(store.localSyncCoordinatorStatus, .ready)
        XCTAssertNil(store.localSyncErrorDescription)
    }

    func testClearHistoryStagesExplicitTombstones() async throws {
        var session = BrowserSession.preview
        session.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/private")),
            title: "Private",
            at: Date(timeIntervalSince1970: 100)
        )
        let historyID = try XCTUnwrap(session.selectedSpace?.history.first?.id)
        let coordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
        try coordinator.stage(session: session)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let store = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence(),
            syncCoordinator: coordinator,
            syncCoalescingDelay: .zero
        )

        store.clearHistory()
        await store.flushPendingSyncPersistence()

        let record = try XCTUnwrap(
            coordinator.journal.records.first {
                $0.id == BrowserSyncRecordID(kind: .history, value: historyID)
            })
        XCTAssertEqual(record.tombstone?.reason, .explicitDelete)
        XCTAssertNil(record.payload)
    }

    func testCloseAndRestoreUseRecoverableSupersessionRatherThanPermanentDelete() async throws {
        let session = BrowserSession.preview
        let coordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        )
        try coordinator.stage(session: session)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let store = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence(),
            syncCoordinator: coordinator,
            syncCoalescingDelay: .zero
        )
        let tabID = try XCTUnwrap(store.selectedSpace?.currentTabs.first?.id)

        store.closeTab(tabID)
        await store.flushPendingSyncPersistence()

        let tabRecordID = BrowserSyncRecordID(kind: .tab, value: tabID.rawValue)
        XCTAssertEqual(
            coordinator.journal.records.first { $0.id == tabRecordID }?.tombstone?.reason,
            .superseded
        )
        XCTAssertNotNil(
            coordinator.journal.records.first {
                $0.id == BrowserSyncRecordID(kind: .archive, value: tabID.rawValue)
            }?.payload)

        store.restoreArchivedTab(tabID)
        await store.flushPendingSyncPersistence()

        XCTAssertNotNil(coordinator.journal.records.first { $0.id == tabRecordID }?.payload)
        XCTAssertEqual(
            coordinator.journal.records.first {
                $0.id == BrowserSyncRecordID(kind: .archive, value: tabID.rawValue)
            }?.tombstone?.reason,
            .superseded
        )
    }

    func testModifiedLinkOpensImmediatelyBelowItsOriginTab() throws {
        let store = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence()
        )
        let spaceID = store.session.selectedSpaceID
        let originID = try XCTUnwrap(
            store.openNewTab(
                url: try XCTUnwrap(URL(string: "https://origin.example")),
                in: spaceID,
                selecting: true
            )
        )

        let openedID = try XCTUnwrap(
            store.openNewTab(
                url: try XCTUnwrap(URL(string: "https://destination.example")),
                in: spaceID,
                selecting: false
            )
        )

        let currentTabIDs = try XCTUnwrap(store.selectedSpace).currentTabs.map(\.id)
        let originIndex = try XCTUnwrap(currentTabIDs.firstIndex(of: originID))
        XCTAssertEqual(currentTabIDs.index(after: originIndex), currentTabIDs.firstIndex(of: openedID))
        XCTAssertEqual(store.selectedTab?.id, originID)
    }

    func testArchiveSelectedTabOnlyClosesACommittedCurrentTab() throws {
        let pinned = BrowserTab(
            title: "Pinned",
            url: try XCTUnwrap(URL(string: "https://example.com/pinned")),
            placement: .pinned
        )
        let current = BrowserTab(
            title: "Current",
            url: try XCTUnwrap(URL(string: "https://example.com/current")),
            placement: .current
        )
        let draft = BrowserTab.startPage()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Commands",
            symbol: "keyboard",
            accent: .teal,
            folders: [],
            tabs: [pinned, current, draft],
            selectedTabID: current.id
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )

        XCTAssertEqual(store.archiveSelectedTab(), current.id)
        XCTAssertEqual(
            store.selectedSpace?.archivedTabs.map { $0.id },
            [current.id]
        )

        store.selectTab(pinned.id)
        XCTAssertNil(store.archiveSelectedTab())
        XCTAssertEqual(store.selectedTab?.id, pinned.id)

        store.selectTab(draft.id)
        XCTAssertNil(store.archiveSelectedTab())
        XCTAssertEqual(store.selectedTab?.id, draft.id)
    }

    func testAdjacentTabSelectionWrapsInsideTheSelectedSpace() throws {
        let tabs = try ["First", "Second", "Third"].map { title in
            BrowserTab(
                title: title,
                url: try XCTUnwrap(
                    URL(string: "https://example.com/\(title.lowercased())")
                ),
                placement: .current
            )
        }
        let selectedSpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Selected",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs[0].id
        )
        let untouchedTab = BrowserTab(
            title: "Untouched",
            url: try XCTUnwrap(URL(string: "https://example.com/untouched")),
            placement: .current
        )
        let untouchedSpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Untouched",
            symbol: "2.circle",
            accent: .orange,
            folders: [],
            tabs: [untouchedTab],
            selectedTabID: untouchedTab.id
        )
        let store = BrowserStore(
            session: BrowserSession(
                spaces: [selectedSpace, untouchedSpace],
                selectedSpaceID: selectedSpace.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )

        XCTAssertEqual(store.selectAdjacentTab(offset: -1), tabs[2].id)
        XCTAssertEqual(store.selectedTab?.id, tabs[2].id)
        XCTAssertEqual(store.selectAdjacentTab(offset: 1), tabs[0].id)
        XCTAssertEqual(store.selectedTab?.id, tabs[0].id)
        XCTAssertEqual(
            store.session.space(id: untouchedSpace.id)?.selectedTabID,
            untouchedTab.id
        )
    }

    func testFocusedWindowTabArchivePreservesAnotherWindowsSpaceSelection() throws {
        let root = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence()
        )
        let focusedWindow = root.makeWindowStore()
        let otherWindow = root.makeWindowStore()
        let work = try XCTUnwrap(focusedWindow.session.spaces.first)
        let personal = try XCTUnwrap(
            focusedWindow.session.spaces.first { $0.id != work.id }
        )
        let workTab = try XCTUnwrap(
            work.currentTabs.first { !$0.isStartPage }
        )
        let personalTab = try XCTUnwrap(personal.tabs.first)
        focusedWindow.selectSpace(work.id)
        focusedWindow.selectTab(workTab.id)
        otherWindow.selectSpace(personal.id)
        otherWindow.selectTab(personalTab.id)

        XCTAssertEqual(focusedWindow.archiveSelectedTab(), workTab.id)

        XCTAssertEqual(otherWindow.selectedSpace?.id, personal.id)
        XCTAssertEqual(otherWindow.selectedTab?.id, personalTab.id)
        XCTAssertTrue(
            try XCTUnwrap(otherWindow.session.space(id: work.id))
                .archivedTabs.contains { $0.id == workTab.id }
        )
    }

    func testDuplicatingSelectedTabCreatesASelectedCurrentCopyInItsOwningSpace() throws {
        let source = BrowserTab(
            title: "Reference",
            url: try XCTUnwrap(URL(string: "https://example.com/reference")),
            placement: .saved
        )
        let other = BrowserTab(
            title: "Other",
            url: try XCTUnwrap(URL(string: "https://example.com/other")),
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [source, other],
            selectedTabID: source.id
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )

        let duplicateID = try XCTUnwrap(store.duplicateSelectedTab())
        let duplicate = try XCTUnwrap(
            store.selectedSpace?.tabs.first { $0.id == duplicateID }
        )

        XCTAssertEqual(store.selectedSpace?.id, space.id)
        XCTAssertEqual(store.selectedTab?.id, duplicateID)
        XCTAssertEqual(duplicate.title, source.title)
        XCTAssertEqual(duplicate.url, source.url)
        XCTAssertEqual(duplicate.placement, .current)
        XCTAssertEqual(store.selectedSpace?.tabs.count, 3)
    }

    func testDuplicatingSelectedTabRejectsTransientStartPageDraft() throws {
        let draft = BrowserTab.startPage()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [draft],
            selectedTabID: draft.id
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence()
        )

        XCTAssertNil(store.duplicateSelectedTab())
        XCTAssertEqual(store.selectedSpace?.tabs, [draft])
        XCTAssertEqual(store.selectedTab?.id, draft.id)
    }

    func testRapidSelectionChangesCoalesceSyncStagingToTheLatestSession() async throws {
        let sessionPersistence = InMemoryBrowserSessionPersistence()
        let syncPersistence = CountingBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: syncPersistence,
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        )
        try coordinator.stage(session: .preview)
        let store = BrowserStore(
            session: .preview,
            persistence: sessionPersistence,
            syncCoordinator: coordinator,
            syncCoalescingDelay: .zero
        )
        let tabs = try XCTUnwrap(store.selectedSpace).tabs
        let selectableTabs = Array(tabs.prefix(3))
        XCTAssertGreaterThanOrEqual(selectableTabs.count, 2)
        let initialSaveCount = syncPersistence.saveCount

        for tab in selectableTabs {
            store.selectTab(tab.id)
        }
        await store.flushPendingSyncPersistence()

        XCTAssertEqual(syncPersistence.saveCount, initialSaveCount + 1)
        XCTAssertEqual(sessionPersistence.session, store.session)
        let selectedID = try XCTUnwrap(store.selectedTab?.id)
        let selectedRecord = coordinator.journal.records.first {
            $0.id == BrowserSyncRecordID(kind: .tab, value: selectedID.rawValue)
        }
        guard case .tab(let syncedTab) = selectedRecord?.payload else {
            return XCTFail("The latest selected tab should be present in the sync journal.")
        }
        XCTAssertEqual(syncedTab.title, store.selectedTab?.title)
        XCTAssertEqual(syncedTab.url, store.selectedTab?.url)
    }

    func testUserDefaultsPersistenceSerializesOffMainAndFlushesTheNewestSnapshot() async throws {
        let suiteName = "BrowserStoreTests.session-persistence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = UserDefaultsBrowserSessionPersistence(
            defaults: defaults,
            faviconStore: InMemoryBrowserFaviconStore(),
            encoder: { session in
                XCTAssertFalse(Thread.isMainThread)
                return try? JSONEncoder().encode(session)
            },
            publisher: { defaults, key, data in
                XCTAssertTrue(Thread.isMainThread)
                defaults.set(data, forKey: key)
            }
        )
        var firstSnapshot = BrowserSession.preview
        let personalID = try XCTUnwrap(
            firstSnapshot.spaces.first { $0.id != firstSnapshot.selectedSpaceID }?.id
        )
        firstSnapshot.selectSpace(personalID)
        var newestSnapshot = firstSnapshot
        newestSnapshot.openTab(
            title: "Newest",
            url: try XCTUnwrap(URL(string: "https://example.com/newest"))
        )

        persistence.save(firstSnapshot)
        persistence.save(newestSnapshot)
        await persistence.flushPendingSaves()

        XCTAssertEqual(persistence.load(), newestSnapshot)
    }

    func testDeletingASpacePurgesCredentialsAndStagesExplicitSyncTombstones() async throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let syncPersistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: syncPersistence,
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        )
        try coordinator.stage(session: .preview)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            session: .preview,
            persistence: persistence,
            credentialVault: vault,
            syncCoordinator: coordinator,
            syncCoalescingDelay: .zero
        )
        let deletedSpace = try XCTUnwrap(store.session.spaces.first)
        let retainedSpace = try XCTUnwrap(
            store.session.spaces.first { $0.id != deletedSpace.id }
        )
        let deletedCredential = try credential(
            spaceID: deletedSpace.id,
            username: "delete-me"
        )
        let retainedCredential = try credential(
            spaceID: retainedSpace.id,
            username: "keep-me"
        )
        try await vault.save(deletedCredential, in: deletedSpace.id)
        try await vault.save(retainedCredential, in: retainedSpace.id)
        let deleter = RecordingSpaceDataDeleter()

        try await store.deleteSpace(deletedSpace.id, dataDeleter: deleter)
        await store.flushPendingSyncPersistence()

        XCTAssertEqual(deleter.deletedSpaces, [deletedSpace])
        XCTAssertNil(store.session.space(id: deletedSpace.id))
        XCTAssertEqual(store.session.selectedSpaceID, retainedSpace.id)
        XCTAssertEqual(persistence.session, store.session)
        XCTAssertTrue(store.deletingSpaceIDs.isEmpty)
        let deletedDescriptors = await vault.descriptors(
            in: deletedSpace.id
        )
        let retainedDescriptors = await vault.descriptors(
            in: retainedSpace.id
        )
        XCTAssertTrue(deletedDescriptors.isEmpty)
        XCTAssertEqual(
            retainedDescriptors,
            [retainedCredential.descriptor]
        )
        let deletedRecord = try XCTUnwrap(
            coordinator.journal.records.first {
                $0.id
                    == BrowserSyncRecordID(
                        kind: .space,
                        value: deletedSpace.id.rawValue
                    )
            }
        )
        XCTAssertNil(deletedRecord.payload)
        XCTAssertEqual(deletedRecord.tombstone?.reason, .explicitDelete)
        XCTAssertEqual(syncPersistence.journal, coordinator.journal)
    }

    func testDataStoreFailureKeepsTheSpaceAndItsCredentialsRetryable() async throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            session: .preview,
            persistence: persistence,
            credentialVault: vault
        )
        let deletedSpace = try XCTUnwrap(store.session.spaces.first)
        let credential = try credential(
            spaceID: deletedSpace.id,
            username: "still-private"
        )
        try await vault.save(credential, in: deletedSpace.id)
        let deleter = RecordingSpaceDataDeleter(error: TestSpaceDeletionError.failed)

        await assertThrowsErrorAsync {
            try await store.deleteSpace(
                deletedSpace.id,
                dataDeleter: deleter
            )
        }

        XCTAssertEqual(deleter.deletedSpaces, [deletedSpace])
        XCTAssertNotNil(store.session.space(id: deletedSpace.id))
        XCTAssertTrue(store.deletingSpaceIDs.isEmpty)
        let descriptors = await vault.descriptors(
            in: deletedSpace.id
        )
        XCTAssertEqual(
            descriptors,
            [credential.descriptor]
        )
    }

    func testDeletingTheLastSpaceIsRefusedBeforeAnyDataStoreMutation() async throws {
        var session = BrowserSession.preview
        session.spaces = [try XCTUnwrap(session.spaces.first)]
        session.selectedSpaceID = try XCTUnwrap(session.spaces.first?.id)
        let store = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence()
        )
        let deleter = RecordingSpaceDataDeleter()

        await assertThrowsErrorAsync(
            expected: BrowserSpaceDeletionError.cannotDeleteLastSpace
        ) {
            try await store.deleteSpace(
                session.selectedSpaceID,
                dataDeleter: deleter
            )
        }

        XCTAssertTrue(deleter.deletedSpaces.isEmpty)
        XCTAssertEqual(store.session.spaces.count, 1)
    }

    func testOpeningATabInASpaceBeingDeletedIsRefusedWithoutChangingSelection() async throws {
        let originalSession = BrowserSession.preview
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(
            session: originalSession,
            persistence: persistence
        )
        let destination = try XCTUnwrap(
            store.session.spaces.first {
                $0.id != store.session.selectedSpaceID
            }
        )
        let sourceSpaceID = store.session.selectedSpaceID
        let sourceTabCount = try XCTUnwrap(
            store.session.space(id: sourceSpaceID)?.tabs.count
        )
        let destinationTabCount = destination.tabs.count
        let deleter = SuspendingBrowserSpaceDataDeleter()
        let deletion = Task {
            try await store.deleteSpace(
                destination.id,
                dataDeleter: deleter
            )
        }
        await deleter.waitUntilDeletionStarts()

        XCTAssertTrue(store.deletingSpaceIDs.contains(destination.id))
        XCTAssertNil(
            store.openNewTab(
                url: try XCTUnwrap(URL(string: "https://deleting.crest.test")),
                in: destination.id,
                selecting: true
            )
        )
        XCTAssertEqual(store.session.selectedSpaceID, sourceSpaceID)
        XCTAssertEqual(
            store.session.space(id: sourceSpaceID)?.tabs.count,
            sourceTabCount
        )
        XCTAssertEqual(
            store.session.space(id: destination.id)?.tabs.count,
            destinationTabCount
        )
        XCTAssertNil(persistence.session)

        deleter.finishDeletion()
        try await deletion.value
        XCTAssertNil(store.session.space(id: destination.id))
    }

    func testMovingATabIntoASpaceBeingDeletedIsRefusedWithoutChangingEitherSpace() async throws {
        let store = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let source = try XCTUnwrap(store.session.selectedSpace)
        let sourceTab = try XCTUnwrap(source.tabs.first)
        let destination = try XCTUnwrap(
            store.session.spaces.first { $0.id != source.id }
        )
        let sourceTabIDs = source.tabs.map(\.id)
        let destinationTabIDs = destination.tabs.map(\.id)
        let deleter = SuspendingBrowserSpaceDataDeleter()
        let deletion = Task {
            try await store.deleteSpace(
                destination.id,
                dataDeleter: deleter
            )
        }
        await deleter.waitUntilDeletionStarts()

        XCTAssertFalse(
            store.canMoveTab(
                sourceTab.id,
                from: source.id,
                into: destination.id
            )
        )
        XCTAssertFalse(
            store.moveTab(
                sourceTab.id,
                from: source.id,
                into: destination.id
            )
        )
        XCTAssertEqual(store.session.space(id: source.id)?.tabs.map(\.id), sourceTabIDs)
        XCTAssertEqual(
            store.session.space(id: destination.id)?.tabs.map(\.id),
            destinationTabIDs
        )

        deleter.finishDeletion()
        try await deletion.value
    }

    func testSelectedSpaceBecomesUnavailableWhileItsDataDeletionIsInFlight() throws {
        let store = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let selectedSpace = try XCTUnwrap(store.selectedSpace)
        let tabCount = selectedSpace.tabs.count

        XCTAssertTrue(store.family.beginDeletingSpace(selectedSpace.id))
        defer { store.family.finishDeletingSpace(selectedSpace.id) }

        XCTAssertNil(store.selectedSpace)
        XCTAssertNil(store.selectedTab)
        XCTAssertNil(store.openNewTab())
        XCTAssertEqual(
            store.session.space(id: selectedSpace.id)?.tabs.count,
            tabCount
        )
    }

    func testStaleDragCannotMoveATabFromAReplacementBrowsingProfile() throws {
        let store = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let source = try XCTUnwrap(store.session.spaces.first)
        let destination = try XCTUnwrap(
            store.session.spaces.first { $0.id != source.id }
        )
        let tab = try XCTUnwrap(source.tabs.first)
        let staleItem = BrowserTabDragItem(
            tabID: tab.id,
            spaceID: source.id,
            profileID: source.profile.id
        )
        let replacement = BrowserSpace(
            id: source.id,
            profile: BrowsingProfile(),
            name: source.name,
            symbol: source.symbol,
            accent: source.accent,
            branding: source.branding,
            folders: source.folders,
            tabs: source.tabs,
            archivedTabs: source.archivedTabs,
            history: source.history,
            browsingPreferences: source.browsingPreferences,
            credentialPreferences: source.credentialPreferences,
            accessPolicy: source.accessPolicy,
            isSavedTabsExpanded: source.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: source.savedTabsExpansionModifiedAt,
            selectedTabID: source.selectedTabID
        )
        let sourceIndex = try XCTUnwrap(
            store.session.spaces.firstIndex { $0.id == source.id }
        )
        store.session.spaces[sourceIndex] = replacement

        XCTAssertFalse(
            store.moveTab(
                staleItem,
                into: BrowserSpaceRuntimeAssignment(space: destination)
            )
        )
        XCTAssertTrue(
            try XCTUnwrap(store.session.space(id: source.id)).contains(tab.id)
        )
        XCTAssertFalse(
            try XCTUnwrap(store.session.space(id: destination.id)).contains(tab.id)
        )
    }

    func testWindowStateStoreRestoresAndPersistsOnlyItsOwnSelection() throws {
        let session = BrowserSession.preview
        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.last)
        let workTabID = try XCTUnwrap(work.tabs.first?.id)
        let personalTabID = try XCTUnwrap(personal.tabs.last?.id)
        let persistence = InMemoryBrowserWindowStatePersistence()
        var savedState = BrowserWindowState(restoring: session)
        savedState.selectTab(personalTabID, in: personal.id, session: session)
        persistence.save(savedState)
        let firstWindow = BrowserWindowStateStore(
            id: savedState.id,
            session: session,
            persistence: persistence
        )
        let secondWindow = BrowserWindowStateStore(
            id: BrowserWindowID(),
            session: session,
            persistence: persistence
        )

        firstWindow.selectTab(workTabID, in: work.id, session: session)

        XCTAssertEqual(firstWindow.selectedTab(in: session)?.id, workTabID)
        XCTAssertEqual(secondWindow.selectedSpaceID, session.selectedSpaceID)
        XCTAssertEqual(
            persistence.load(id: firstWindow.id)?.selectedTab(in: session)?.id,
            workTabID
        )
        XCTAssertEqual(
            persistence.load(id: secondWindow.id)?.selectedTab(in: session)?.id,
            session.selectedTab?.id
        )
    }

    func testWindowStateStoreCapturesSelectionFromItsWindowBrowser() throws {
        let persistence = InMemoryBrowserWindowStatePersistence()
        let browser = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence()
        )
        let windowID = BrowserWindowID()
        let stateStore = BrowserWindowStateStore(
            id: windowID,
            session: browser.session,
            persistence: persistence
        )
        let personal = try XCTUnwrap(browser.session.spaces.last)
        let personalTabID = try XCTUnwrap(personal.tabs.last?.id)

        browser.selectSpace(personal.id)
        browser.selectTab(personalTabID)
        stateStore.captureSelection(from: browser.session)

        let restoredState = try XCTUnwrap(persistence.load(id: windowID))
        XCTAssertEqual(restoredState.selectedSpaceID, personal.id)
        XCTAssertEqual(
            restoredState.selectedTab(in: browser.session)?.id,
            personalTabID
        )
    }

    func testWindowStateStoreRecordsTheTabThatActuallyRenders() throws {
        let persistence = InMemoryBrowserWindowStatePersistence()
        let session = BrowserSession.preview
        let stateStore = BrowserWindowStateStore(
            id: BrowserWindowID(),
            session: session,
            persistence: persistence
        )
        let renderedSpace = try XCTUnwrap(session.spaces.last)
        let renderedTabID = try XCTUnwrap(renderedSpace.tabs.last?.id)

        stateStore.recordRenderedTab(
            renderedTabID,
            in: renderedSpace.id,
            session: session
        )

        let persistedState = try XCTUnwrap(persistence.load(id: stateStore.id))
        XCTAssertEqual(persistedState.selectedSpaceID, renderedSpace.id)
        XCTAssertEqual(
            persistedState.selectedTab(in: session)?.id,
            renderedTabID
        )
    }

    func testWindowStateStorePersistsChromeOnlyForItsOwningWindow() {
        let session = BrowserSession.preview
        let persistence = InMemoryBrowserWindowStatePersistence()
        let firstWindow = BrowserWindowStateStore(
            id: BrowserWindowID(),
            session: session,
            persistence: persistence
        )
        let secondWindow = BrowserWindowStateStore(
            id: BrowserWindowID(),
            session: session,
            persistence: persistence
        )

        firstWindow.captureSidebar(width: 364, isPresented: false)
        secondWindow.captureSidebar(width: 278, isPresented: true)

        XCTAssertEqual(persistence.load(id: firstWindow.id)?.sidebarWidth, 364)
        XCTAssertEqual(
            persistence.load(id: firstWindow.id)?.sidebarIsPresented,
            false
        )
        XCTAssertEqual(persistence.load(id: secondWindow.id)?.sidebarWidth, 278)
        XCTAssertEqual(
            persistence.load(id: secondWindow.id)?.sidebarIsPresented,
            true
        )
    }

    func testWindowStoresShareBrowserMutationsButKeepIndependentSelections() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let firstWindow = BrowserStore(session: .preview, persistence: persistence)
        let secondWindow = firstWindow.makeWindowStore()
        let work = try XCTUnwrap(firstWindow.session.spaces.first)
        let personal = try XCTUnwrap(firstWindow.session.spaces.last)
        let workTabID = try XCTUnwrap(work.tabs.first?.id)
        let personalTabID = try XCTUnwrap(personal.tabs.last?.id)
        let newURL = try XCTUnwrap(URL(string: "https://multiwindow.crest.test"))

        firstWindow.selectSpace(personal.id)
        firstWindow.selectTab(personalTabID)
        secondWindow.selectSpace(work.id)
        secondWindow.selectTab(workTabID)
        let openedTabID = try XCTUnwrap(firstWindow.openNewTab(url: newURL))

        XCTAssertEqual(firstWindow.selectedSpace?.id, personal.id)
        XCTAssertEqual(firstWindow.selectedTab?.id, openedTabID)
        XCTAssertEqual(secondWindow.selectedSpace?.id, work.id)
        XCTAssertEqual(secondWindow.selectedTab?.id, workTabID)
        XCTAssertEqual(
            secondWindow.session.space(id: personal.id)?.tabs.first { $0.id == openedTabID }?.url,
            newURL
        )
        XCTAssertEqual(
            firstWindow.session.spaces.map(\.profile.id),
            secondWindow.session.spaces.map(\.profile.id)
        )
    }

    func testSceneActivationSweepArchivesExpiredCurrentTabsInALongLivedSession() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fixture = Self.makeCleanupSweepFixture(now: now)
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: fixture.session, persistence: persistence)

        // Only launch and explicit actions used to sweep, so a store that is
        // already running still holds the expired tab before activation.
        let beforeSweep = try XCTUnwrap(store.session.space(id: fixture.sweepingSpaceID))
        XCTAssertTrue(beforeSweep.contains(fixture.expiredTabID))
        XCTAssertTrue(beforeSweep.archivedTabs.isEmpty)

        XCTAssertTrue(store.sweepExpiredCurrentTabs(now: now))

        let swept = try XCTUnwrap(store.session.space(id: fixture.sweepingSpaceID))
        XCTAssertFalse(swept.contains(fixture.expiredTabID))
        XCTAssertEqual(swept.archivedTabs.map(\.id), [fixture.expiredTabID])
        XCTAssertEqual(swept.archivedTabs.first?.reason, .autoCleanup)
        XCTAssertEqual(swept.archivedTabs.first?.archivedAt, now)
        // The stale selected tab and the start page stay put.
        XCTAssertTrue(swept.contains(fixture.selectedTabID))
        XCTAssertEqual(swept.selectedTabID, fixture.selectedTabID)
        XCTAssertTrue(swept.contains(fixture.startPageID))
        XCTAssertEqual(
            persistence.session?.space(id: fixture.sweepingSpaceID)?.archivedTabs.map(\.id),
            [fixture.expiredTabID]
        )
    }

    func testSceneActivationSweepRespectsEverySpaceCleanupPolicy() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let fixture = Self.makeCleanupSweepFixture(now: now)
        let store = BrowserStore(
            session: fixture.session,
            persistence: InMemoryBrowserSessionPersistence()
        )

        store.sweepExpiredCurrentTabs(now: now)

        let neverSpace = try XCTUnwrap(store.session.space(id: fixture.neverSpaceID))
        XCTAssertTrue(neverSpace.contains(fixture.neverPolicyTabID))
        XCTAssertTrue(neverSpace.archivedTabs.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(store.session.space(id: fixture.sweepingSpaceID)).archivedTabs.count,
            1
        )
    }

    func testCleanupSweepsCollapseAcrossWindowsUntilTheSpacingElapses() throws {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let fixture = Self.makeCleanupSweepFixture(now: now)
        let store = BrowserStore(
            session: fixture.session,
            persistence: InMemoryBrowserSessionPersistence()
        )
        let secondWindow = store.makeWindowStore()

        XCTAssertTrue(store.sweepExpiredCurrentTabs(now: now))
        // Windows share one session, so the second window must not sweep again.
        XCTAssertFalse(secondWindow.sweepExpiredCurrentTabs(now: now))
        XCTAssertFalse(
            store.sweepExpiredCurrentTabs(
                now: now.addingTimeInterval(
                    BrowserCurrentTabCleanupSchedule.minimumSweepSpacing - 1
                )
            )
        )
        XCTAssertTrue(
            secondWindow.sweepExpiredCurrentTabs(
                now: now.addingTimeInterval(
                    BrowserCurrentTabCleanupSchedule.minimumSweepSpacing
                )
            )
        )
        XCTAssertEqual(
            secondWindow.session.space(id: fixture.sweepingSpaceID)?.archivedTabs.map(\.id),
            [fixture.expiredTabID]
        )
    }

    func testPeriodicCleanupSweepCadenceIsPinnedForActiveScenes() {
        let now = Date(timeIntervalSince1970: 4_000_000)

        XCTAssertEqual(BrowserCurrentTabCleanupSchedule.sweepInterval, 15 * 60)
        XCTAssertEqual(BrowserCurrentTabCleanupSchedule.minimumSweepSpacing, 60)
        XCTAssertTrue(
            BrowserCurrentTabCleanupSchedule.allowsSweep(lastSweptAt: nil, now: now)
        )
        XCTAssertFalse(
            BrowserCurrentTabCleanupSchedule.allowsSweep(
                lastSweptAt: now,
                now: now.addingTimeInterval(59)
            )
        )
        XCTAssertTrue(
            BrowserCurrentTabCleanupSchedule.allowsSweep(
                lastSweptAt: now,
                now: now.addingTimeInterval(60)
            )
        )
        XCTAssertTrue(
            BrowserCurrentTabCleanupSchedule.allowsSweep(
                lastSweptAt: now,
                now: now.addingTimeInterval(BrowserCurrentTabCleanupSchedule.sweepInterval)
            )
        )
        // A backwards clock adjustment must not wedge the sweep shut.
        XCTAssertTrue(
            BrowserCurrentTabCleanupSchedule.allowsSweep(
                lastSweptAt: now,
                now: now.addingTimeInterval(-60 * 60)
            )
        )
    }

    func testReleaseSoakFixtureBuildsThirteenCurrentTabsInsideOneLoopbackProfile() throws {
        let session = try XCTUnwrap(
            BrowserPerformanceSoakFixture.makeSession(
                baseURLString: "http://127.0.0.1:18768/",
                rawTabCount: "13",
                runID: "release-run"
            )
        )
        XCTAssertEqual(session.spaces.count, 1)
        let space = try XCTUnwrap(session.spaces.first)

        XCTAssertEqual(space.name, "Performance")
        XCTAssertEqual(space.tabs.count, 13)
        XCTAssertEqual(Set(space.tabs.map(\.placement)), [.current])
        XCTAssertEqual(Set(space.tabs.compactMap { $0.url?.host() }), ["127.0.0.1"])
        XCTAssertEqual(space.selectedTabID, space.tabs.first?.id)
        XCTAssertEqual(space.browsingPreferences.currentTabCleanupPolicy, .never)
        XCTAssertEqual(space.browsingPreferences.contentBlockingPolicy, .off)
        XCTAssertTrue(space.tabs[0].url?.absoluteString.contains("mutate=1") == true)
        XCTAssertTrue(space.tabs[1].url?.absoluteString.contains("video=1") == true)
        XCTAssertEqual(
            Set(session.tabRuntimeAssignments.map(\.profileID)),
            [space.profile.id]
        )
    }

    func testReleaseSoakFixtureRejectsNonLoopbackAndMalformedInputs() {
        XCTAssertNil(
            BrowserPerformanceSoakFixture.makeSession(
                baseURLString: "https://example.com/",
                rawTabCount: "13",
                runID: "release-run"
            )
        )
        XCTAssertNil(
            BrowserPerformanceSoakFixture.makeSession(
                baseURLString: "http://127.0.0.1:18768/",
                rawTabCount: "1",
                runID: "release-run"
            )
        )
        XCTAssertNil(
            BrowserPerformanceSoakFixture.makeSession(
                baseURLString: "http://127.0.0.1:18768/",
                rawTabCount: "13",
                runID: "../../hostile"
            )
        )
    }

    private struct CleanupSweepFixture {
        let session: BrowserSession
        let sweepingSpaceID: SpaceID
        let neverSpaceID: SpaceID
        let expiredTabID: TabID
        let selectedTabID: TabID
        let startPageID: TabID
        let neverPolicyTabID: TabID
    }

    /// A session that has been running long enough for cleanup to matter: one
    /// Space on the default 12 hour policy holding a stale selected tab, a stale
    /// start page and a stale unselected tab, plus one Space set to `.never`.
    private static func makeCleanupSweepFixture(now: Date) -> CleanupSweepFixture {
        let selected = BrowserTab(
            title: "Reading now",
            url: URL(string: "https://example.com/selected"),
            placement: .current,
            lastActivatedAt: now.addingTimeInterval(-13 * 60 * 60)
        )
        let startPage = BrowserTab.startPage(
            lastActivatedAt: now.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        let expired = BrowserTab(
            title: "Old research",
            url: URL(string: "https://example.com/old"),
            placement: .current,
            lastActivatedAt: now.addingTimeInterval(-13 * 60 * 60)
        )
        let pinned = BrowserTab(
            title: "Pinned",
            url: URL(string: "https://example.com/pinned"),
            placement: .pinned,
            lastActivatedAt: now.addingTimeInterval(-40 * 24 * 60 * 60)
        )
        let sweepingSpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [pinned, selected, startPage, expired],
            browsingPreferences: BrowserSpaceBrowsingPreferences(
                searchProvider: .google,
                currentTabCleanupPolicy: .after12Hours
            ),
            selectedTabID: selected.id
        )
        let neverSelected = BrowserTab(
            title: "Personal",
            url: URL(string: "https://example.com/personal"),
            placement: .current,
            lastActivatedAt: now
        )
        let neverPolicyTab = BrowserTab(
            title: "Kept indefinitely",
            url: URL(string: "https://example.com/keep"),
            placement: .current,
            lastActivatedAt: now.addingTimeInterval(-31 * 24 * 60 * 60)
        )
        let neverSpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Personal",
            symbol: "house.fill",
            accent: .teal,
            folders: [],
            tabs: [neverSelected, neverPolicyTab],
            browsingPreferences: BrowserSpaceBrowsingPreferences(
                searchProvider: .duckDuckGo,
                currentTabCleanupPolicy: .never
            ),
            selectedTabID: neverSelected.id
        )
        return CleanupSweepFixture(
            session: BrowserSession(
                spaces: [sweepingSpace, neverSpace],
                selectedSpaceID: sweepingSpace.id
            ),
            sweepingSpaceID: sweepingSpace.id,
            neverSpaceID: neverSpace.id,
            expiredTabID: expired.id,
            selectedTabID: selected.id,
            startPageID: startPage.id,
            neverPolicyTabID: neverPolicyTab.id
        )
    }

    private func credential(
        spaceID: SpaceID,
        username: String
    ) throws -> BrowserCredential {
        let origin = try XCTUnwrap(
            CredentialOrigin(
                url: try XCTUnwrap(
                    URL(string: "https://credentials.crest.test")
                )
            )
        )
        return BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: spaceID,
                origin: origin,
                username: username
            ),
            password: "secret"
        )
    }
}

@MainActor
private final class RecordingSpaceDataDeleter: BrowserSpaceDataDeleting {
    private(set) var deletedSpaces: [BrowserSpace] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func deleteData(for space: BrowserSpace) async throws {
        deletedSpaces.append(space)
        if let error {
            throw error
        }
    }
}

private enum TestSpaceDeletionError: Error {
    case failed
}

@MainActor
private func assertThrowsErrorAsync(
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected operation to throw", file: file, line: line)
    } catch {}
}

@MainActor
private func assertThrowsErrorAsync<T>(
    expected: T,
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async where T: Error & Equatable {
    do {
        try await operation()
        XCTFail("Expected operation to throw", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? T, expected, file: file, line: line)
    }
}

private final class CountingBrowserSyncJournalPersistence: BrowserSyncJournalPersisting {
    private(set) var journal: BrowserSyncJournal?
    private(set) var saveCount = 0

    func load() throws -> BrowserSyncJournal? {
        journal
    }

    func save(_ journal: BrowserSyncJournal) throws {
        self.journal = journal
        saveCount += 1
    }
}

/// What each mutation tells storage it changed. A save that claims too much is a
/// performance regression, and a save that claims too little loses state, so both
/// directions are asserted per mutation.
@MainActor
final class BrowserStoreSaveScopeTests: XCTestCase {
    private typealias Storage = UserDefaultsBrowserSessionPersistence

    func testAPageTitleChangePersistsTheCoreAlone() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let url = try XCTUnwrap(store.selectedTab?.url ?? URL(string: "https://example.com"))
        store.updateSelectedTabFromPage(url: url, title: "First title")

        store.updateSelectedTabFromPage(url: url, title: "A title the page keeps rewriting")

        XCTAssertEqual(persistence.savedScopes.last, .core)
        XCTAssertEqual(store.selectedTab?.title, "A title the page keeps rewriting")
    }

    func testCapturingAFaviconPersistsThatTabsIconAndTheCore() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let spaceID = try XCTUnwrap(store.selectedSpace?.id)
        let tab = try XCTUnwrap(store.selectedSpace?.tabs.first { $0.url != nil })
        let url = try XCTUnwrap(tab.url)

        store.cacheAutomaticTabFavicon(
            Data("captured".utf8),
            iconAccent: BrowserTabIconAccent(red: 0.2, green: 0.4, blue: 0.6),
            url: url,
            for: tab.id,
            in: spaceID
        )

        XCTAssertEqual(persistence.savedScopes.last, .favicon(for: tab.id))
    }

    /// An unfocused card claims exactly what the focused one does: a title rewrite
    /// is the core alone, and only an icon change reaches that tab's favicon store.
    func testACardPageClaimsTheSameSaveScopesAsTheFocusedOne() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let space = try XCTUnwrap(store.selectedSpace)
        let member = try XCTUnwrap(space.tabs.first { $0.url != nil })
        let assignment = BrowserSpaceRuntimeAssignment(space: space)

        store.updateTabFromPage(
            url: member.url,
            title: "A title the card keeps rewriting",
            for: member.id,
            matching: assignment
        )
        XCTAssertEqual(persistence.savedScopes.last, .core)

        store.updateTabFromPage(
            url: member.url,
            title: "A title the card keeps rewriting",
            faviconData: Data("captured".utf8),
            iconAccent: BrowserTabIconAccent(red: 0.2, green: 0.4, blue: 0.6),
            for: member.id,
            matching: assignment
        )
        XCTAssertEqual(persistence.savedScopes.last, .favicon(for: member.id))
    }

    func testRecordingAVisitPersistsOnlyThatSpacesHistory() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let selectedSpaceID = store.session.selectedSpaceID
        let otherSpaceID = try XCTUnwrap(store.session.spaces.last { $0.id != selectedSpaceID }?.id)

        store.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/read")),
            title: "Read"
        )
        XCTAssertEqual(persistence.savedScopes.last, .history(in: selectedSpaceID))

        store.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/elsewhere")),
            title: "Elsewhere",
            in: otherSpaceID
        )
        XCTAssertEqual(persistence.savedScopes.last, .history(in: otherSpaceID))
        XCTAssertEqual(store.session.space(id: selectedSpaceID)?.history.count, 1)
        XCTAssertEqual(store.session.space(id: otherSpaceID)?.history.count, 1)
    }

    func testClearingHistoryPersistsOnlyTheSelectedSpacesHistory() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let selectedSpaceID = store.session.selectedSpaceID
        store.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/read")),
            title: "Read"
        )

        store.clearHistory()

        XCTAssertEqual(persistence.savedScopes.last, .history(in: selectedSpaceID))
        XCTAssertTrue(try XCTUnwrap(store.session.space(id: selectedSpaceID)?.history.isEmpty))
    }

    func testClearingCapturedSpaceHistoryDoesNotRetargetAfterSelectionChanges() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let initiatingSpace = try XCTUnwrap(store.selectedSpace)
        let laterSelectedSpace = try XCTUnwrap(
            store.session.spaces.first { $0.id != initiatingSpace.id }
        )
        let request = BrowserSidebarClearHistoryConfirmation(
            assignment: BrowserSpaceRuntimeAssignment(space: initiatingSpace),
            spaceName: initiatingSpace.name
        )
        store.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/initiating")),
            title: "Initiating"
        )
        store.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/later-selected")),
            title: "Later selected",
            in: laterSelectedSpace.id
        )

        store.selectSpace(laterSelectedSpace.id)
        XCTAssertTrue(store.clearHistory(matching: request.assignment))

        XCTAssertEqual(store.session.selectedSpaceID, laterSelectedSpace.id)
        XCTAssertTrue(
            try XCTUnwrap(store.session.space(id: initiatingSpace.id))
                .history.isEmpty
        )
        XCTAssertEqual(
            try XCTUnwrap(store.session.space(id: laterSelectedSpace.id))
                .history.count,
            1
        )
        XCTAssertEqual(
            persistence.savedScopes.last,
            .history(in: initiatingSpace.id)
        )
    }

    func testClearingCapturedHistoryRejectsAReplacementBrowsingProfile() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(
            session: .preview,
            persistence: persistence,
            browsingMode: .privateBrowsing
        )
        let initiatingSpace = try XCTUnwrap(store.selectedSpace)
        store.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/private")),
            title: "Private"
        )
        let request = BrowserSidebarClearHistoryConfirmation(
            assignment: BrowserSpaceRuntimeAssignment(space: initiatingSpace),
            spaceName: initiatingSpace.name
        )
        let currentSpace = try XCTUnwrap(store.selectedSpace)
        let replacement = BrowserSpace(
            id: currentSpace.id,
            profile: BrowsingProfile(
                id: UUID(
                    uuid: (
                        0x43, 0x4C, 0x45, 0x41, 0x52, 0x48, 0x49, 0x53,
                        0x54, 0x4F, 0x52, 0x59, 0x00, 0x00, 0x00, 0x01
                    )
                )
            ),
            name: currentSpace.name,
            symbol: currentSpace.symbol,
            accent: currentSpace.accent,
            branding: currentSpace.branding,
            folders: currentSpace.folders,
            tabs: currentSpace.tabs,
            archivedTabs: currentSpace.archivedTabs,
            history: currentSpace.history,
            browsingPreferences: currentSpace.browsingPreferences,
            credentialPreferences: currentSpace.credentialPreferences,
            accessPolicy: currentSpace.accessPolicy,
            isSavedTabsExpanded: currentSpace.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt:
                currentSpace.savedTabsExpansionModifiedAt,
            selectedTabID: currentSpace.selectedTabID
        )
        let spaceIndex = try XCTUnwrap(
            store.session.spaces.firstIndex { $0.id == initiatingSpace.id }
        )
        store.session.spaces[spaceIndex] = replacement

        XCTAssertFalse(store.clearHistory(matching: request.assignment))
        XCTAssertEqual(
            store.session.space(id: replacement.id)?.history.count,
            1
        )
    }

    func testRestoringCapturedArchiveRejectsAReplacementBrowsingProfile() throws {
        let store = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let url = try XCTUnwrap(URL(string: "https://example.com/archive"))
        let tabID = try XCTUnwrap(store.openNewTab(url: url))
        store.closeTab(tabID)
        let original = try XCTUnwrap(store.selectedSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: original)
        XCTAssertTrue(original.archivedTabs.contains(where: { $0.id == tabID }))
        let replacement = BrowserSpace(
            id: original.id,
            profile: BrowsingProfile(),
            name: original.name,
            symbol: original.symbol,
            accent: original.accent,
            branding: original.branding,
            folders: original.folders,
            tabs: original.tabs,
            archivedTabs: original.archivedTabs,
            history: original.history,
            browsingPreferences: original.browsingPreferences,
            credentialPreferences: original.credentialPreferences,
            accessPolicy: original.accessPolicy,
            isSavedTabsExpanded: original.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: original.savedTabsExpansionModifiedAt,
            selectedTabID: original.selectedTabID
        )
        let index = try XCTUnwrap(
            store.session.spaces.firstIndex { $0.id == original.id }
        )
        store.session.spaces[index] = replacement

        XCTAssertFalse(store.restoreArchivedTab(tabID, matching: assignment))
        XCTAssertTrue(
            try XCTUnwrap(store.session.space(id: original.id))
                .archivedTabs.contains(where: { $0.id == tabID })
        )
    }

    func testTabAndSpaceStructureChangesPersistTheCore() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let spaceID = try XCTUnwrap(store.selectedSpace?.id)

        store.openNewTab(url: try XCTUnwrap(URL(string: "https://example.com/opened")))
        XCTAssertEqual(persistence.savedScopes.last, .core)

        let opened = try XCTUnwrap(store.selectedTab?.id)
        store.selectTab(opened)
        XCTAssertEqual(persistence.savedScopes.last, .core)

        XCTAssertTrue(store.setTabCustomTitle("Named by hand", for: opened, in: spaceID))
        XCTAssertEqual(persistence.savedScopes.last, .core)

        XCTAssertTrue(store.setTabKeepsPageLoaded(true, for: opened, in: spaceID))
        XCTAssertEqual(persistence.savedScopes.last, .core)
        XCTAssertEqual(store.selectedTab?.keepsPageLoaded, true)

        store.pinSelectedTab()
        XCTAssertEqual(persistence.savedScopes.last, .core)

        store.addSpace()
        XCTAssertEqual(persistence.savedScopes.last, .core)
    }

    func testSavedTabsAndFolderDisclosurePersistTheCore() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let spaceID = try XCTUnwrap(store.selectedSpace?.id)
        let folderID = try XCTUnwrap(store.selectedSpace?.folders.first?.id)

        XCTAssertTrue(store.setSavedTabsExpanded(false, in: spaceID))
        XCTAssertEqual(persistence.savedScopes.last, .core)
        XCTAssertEqual(store.selectedSpace?.isSavedTabsExpanded, false)

        XCTAssertTrue(
            store.setFolderCollapsed(folderID, in: spaceID, isCollapsed: true)
        )
        XCTAssertEqual(persistence.savedScopes.last, .core)
        XCTAssertEqual(
            store.selectedSpace?.folders.first { $0.id == folderID }?.isCollapsed,
            true
        )
    }

    func testDuplicatingATabPersistsTheCopiedIcon() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        let spaceID = try XCTUnwrap(store.selectedSpace?.id)
        let source = try XCTUnwrap(store.selectedSpace?.tabs.first { $0.url != nil })

        let duplicateID = try XCTUnwrap(store.duplicateTab(source.id, in: spaceID))

        XCTAssertEqual(persistence.savedScopes.last, .favicon(for: duplicateID))
    }

    func testAnImportStillRewritesEverything() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let store = BrowserStore(session: .preview, persistence: persistence)
        var imported = BrowserSession.preview
        imported.recordVisit(
            url: try XCTUnwrap(URL(string: "https://example.com/imported")),
            title: "Imported",
            in: imported.selectedSpaceID
        )

        try store.importPortableArchive(
            BrowserPortableImport(
                spaces: imported.spaces,
                summary: BrowserPortableImportSummary(
                    spaceCount: imported.spaces.count,
                    folderCount: imported.spaces.reduce(0) { $0 + $1.folders.count },
                    liveTabCount: imported.spaces.reduce(0) { $0 + $1.tabs.count },
                    archivedTabCount: imported.spaces.reduce(0) { $0 + $1.archivedTabs.count },
                    historyEntryCount: imported.spaces.reduce(0) { $0 + $1.history.count }
                )
            )
        )

        XCTAssertEqual(
            persistence.savedScopes.last,
            .everything,
            "Imported Spaces bring their own history and icons."
        )
    }

    /// The end-to-end claim: a page that rewrites its title touches one key.
    func testATitleChangeWritesOnlyTheSessionCoreThroughRealStorage() async throws {
        let suiteName = "BrowserStoreSaveScopeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let recorder = BrowserSessionStorageWriteRecorder()
        let favicons = SpyingBrowserFaviconStore()
        let persistence = UserDefaultsBrowserSessionPersistence(
            defaults: defaults,
            faviconStore: favicons,
            publisher: recorder.publisher,
            remover: recorder.remover
        )
        let store = BrowserStore(session: .preview, persistence: persistence)
        let url = try XCTUnwrap(URL(string: "https://example.com/spa"))
        store.openNewTab(url: url)
        store.recordVisit(url: url, title: "Seeded so the history key exists")
        await store.flushPendingSyncPersistence()
        let historyKey = Storage.historyKey(for: store.session.selectedSpaceID)
        XCTAssertNotNil(defaults.data(forKey: historyKey))
        recorder.reset()
        favicons.reset()

        for index in 1...5 {
            store.updateSelectedTabFromPage(url: url, title: "Title \(index)")
        }
        await store.flushPendingSyncPersistence()

        XCTAssertEqual(
            Set(recorder.writtenKeys),
            [Storage.coreKey],
            "A title change may not reach history or the favicon store."
        )
        XCTAssertEqual(recorder.byteCount(forKey: historyKey), 0)
        XCTAssertTrue(favicons.reconciledTabIDs.isEmpty)
        XCTAssertTrue(recorder.removedKeys.isEmpty)
    }
}
