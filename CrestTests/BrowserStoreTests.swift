import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserStoreTests: XCTestCase {
    func testCrossSpaceMovesPreserveSelectionsAndReturnToThePreviouslyActiveSourceTab() throws {
        for route in 0..<3 {
            for movesSelectedTab in [false, true] {
                let session = BrowserSession.preview
                let source = try XCTUnwrap(session.spaces.first)
                let destination = try XCTUnwrap(session.spaces.last)
                let previous = try XCTUnwrap(source.pinnedTabs.last)
                let moved = try XCTUnwrap(source.savedTabs.first)
                let preferences = BrowserLinkPreferenceStore(persistence: InMemoryBrowserLinkPreferencesPersistence())
                preferences.followsTabsMovedToAnotherSpace = false
                let store = BrowserStore(
                    session: session, linkPreferences: preferences)
                store.selectSpace(destination.id)
                let destinationSelection = try XCTUnwrap(store.selectedTabID(in: destination.id))
                store.selectSpace(source.id)
                store.selectTab(previous.id)
                if movesSelectedTab { store.selectTab(moved.id) }
                let item = BrowserTabDragItem(
                    tabID: moved.id, spaceID: source.id, profileID: source.profile.id)
                if route != 0 { store.selectSpace(destination.id) }

                switch route {
                case 0:
                    XCTAssertTrue(store.moveTab(moved.id, from: source.id, into: destination.id))
                case 1:
                    XCTAssertTrue(store.moveTab(item, to: .saved))
                default:
                    XCTAssertTrue(store.moveTab(moved.id, from: source.id, to: .saved))
                }

                XCTAssertEqual(store.selectedSpaceID, route == 0 ? source.id : destination.id)
                XCTAssertEqual(store.selectedTabID(in: source.id), previous.id)
                XCTAssertEqual(store.selectedTabID(in: destination.id), destinationSelection)
                XCTAssertEqual(
                    store.session.space(id: destination.id)?.tabs.first { $0.id == moved.id }?.url, moved.url)
            }
        }
    }

    func testMovingTheOnlyTabRespectsFollowPreferenceWithoutSelectingAnEmptyDestination() throws {
        for follows in [true, false] {
            var session = BrowserSession.preview
            let moved = try XCTUnwrap(session.spaces[0].currentTabs.first)
            session.spaces[0].tabs = [moved]
            session.spaces[1].tabs = []
            let sourceID = session.spaces[0].id
            let destinationID = session.spaces[1].id
            let preferences = BrowserLinkPreferenceStore(persistence: InMemoryBrowserLinkPreferencesPersistence())
            XCTAssertTrue(preferences.followsTabsMovedToAnotherSpace)
            preferences.followsTabsMovedToAnotherSpace = follows
            let store = BrowserStore(
                session: session, linkPreferences: preferences)

            XCTAssertTrue(store.moveTab(moved.id, from: sourceID, into: destinationID))

            XCTAssertTrue(try XCTUnwrap(store.session.space(id: sourceID)).tabs.isEmpty)
            XCTAssertNil(store.selectedTabID(in: sourceID))
            XCTAssertEqual(store.selectedSpaceID, follows ? destinationID : sourceID)
            XCTAssertEqual(store.selectedTabID(in: destinationID), follows ? moved.id : nil)
            XCTAssertEqual(store.consumeMovedTabActivation(), follows)
            XCTAssertFalse(store.consumeMovedTabActivation())
        }
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
            tabs: [first]
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space])
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

    func testNewTabsOpenAfterTheFocusedSplitGroup() throws {
        let groupID = SplitGroupID()
        let head = BrowserTab(
            title: "Head",
            url: URL(string: "https://head.example"),
            placement: .current,
            splitGroupID: groupID
        )
        let tail = BrowserTab(
            title: "Tail",
            url: URL(string: "https://tail.example"),
            placement: .current,
            splitGroupID: groupID
        )
        let trailing = BrowserTab(
            title: "Trailing",
            url: URL(string: "https://trailing.example"),
            placement: .current
        )
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [head, tail, trailing]
        )

        let startPageStore = BrowserStore(
            session: BrowserSession(spaces: [space])
        )
        let startPageID = try XCTUnwrap(startPageStore.openNewTab())
        XCTAssertEqual(
            try XCTUnwrap(startPageStore.selectedSpace).currentTabs.map(\.id),
            [head.id, tail.id, startPageID, trailing.id]
        )

        let navigatedStore = BrowserStore(
            session: BrowserSession(spaces: [space])
        )
        let navigatedID = try XCTUnwrap(
            navigatedStore.openNewTab(
                url: try XCTUnwrap(URL(string: "https://new.example"))
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(navigatedStore.selectedSpace).currentTabs.map(\.id),
            [head.id, tail.id, navigatedID, trailing.id]
        )
    }

    func testFreshInstallSeedPersistsButNeverStagesBeforeCloudBootstrap() async throws {
        let review = try BrowserStore.isolatedLaunch(
            core: CrestCore(),
            launchEnvironment: BrowserLaunchEnvironment(
                values: ["CREST_ISOLATED_SESSION": "1", "CREST_ISOLATED_CLOUD_SYNC_ID": "review"],
                isXCTestRuntime: false))
        await review.flushPendingSyncPersistence()
        XCTAssertTrue(review.session.hasDisposableSeedState)
        let reviewRecords = await review.cloudSyncRecords()
        XCTAssertTrue(reviewRecords.isEmpty)

        let syncPersistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: syncPersistence,
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        )
        let store = BrowserStore(
            session: .freshInstallSeed,
            syncCoordinator: coordinator
        )

        store.openNewTab(
            url: try XCTUnwrap(URL(string: "https://example.com/before-first-sync"))
        )
        await store.flushPendingSyncPersistence()
        let outboundRecords = await store.cloudSyncRecords()
        let outboundPendingRecordIDs = await store.cloudSyncPendingRecordIDs()

        XCTAssertTrue(store.session.hasDisposableSeedState)
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
        let originalSpaceID = store.selectedSpaceID
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
        store.seedVisit(to: url, titled: "Private account")
        XCTAssertFalse(try XCTUnwrap(store.selectedSpace).history.isEmpty)
        XCTAssertNotEqual(store.selectedTab?.id, originalTabID)

        store.resetPrivateBrowsingSession()

        XCTAssertNotEqual(store.selectedSpaceID, originalSpaceID)
        XCTAssertNotEqual(store.selectedSpace?.profile.id, originalProfileID)
        XCTAssertNotEqual(store.selectedTab?.id, originalTabID)
        XCTAssertEqual(store.session.spaces.count, 1)
        XCTAssertEqual(store.selectedSpace?.tabs.count, 1)
        XCTAssertTrue(try XCTUnwrap(store.selectedTab).isStartPage)
        XCTAssertTrue(try XCTUnwrap(store.selectedSpace).history.isEmpty)
        XCTAssertTrue(try XCTUnwrap(store.selectedSpace).archivedTabs.isEmpty)
    }

    func testOpeningABackgroundTabPreservesSelectionAndUsesTheExactOwningSpace() throws {
        let store = BrowserStore(session: .preview)
        let selectedSpaceID = store.selectedSpaceID
        let targetSpace = try XCTUnwrap(
            store.session.spaces.first { $0.id != selectedSpaceID }
        )
        store.selectSpace(targetSpace.id)
        store.selectSpace(selectedSpaceID)
        let selectedTabID = try XCTUnwrap(store.selectedTab?.id)
        let targetSelectedTabID = try XCTUnwrap(store.selectedTabID(in: targetSpace.id))
        let targetCount = targetSpace.tabs.count
        let url = try XCTUnwrap(URL(string: "https://example.com/background"))

        let openedID = try XCTUnwrap(
            store.openNewTab(
                url: url,
                in: targetSpace.id,
                selecting: false
            )
        )

        XCTAssertEqual(store.selectedSpaceID, selectedSpaceID)
        XCTAssertEqual(store.selectedTab?.id, selectedTabID)
        XCTAssertEqual(store.selectedTabID(in: targetSpace.id), targetSelectedTabID)
        XCTAssertEqual(store.session.space(id: targetSpace.id)?.tabs.count, targetCount + 1)
        XCTAssertEqual(
            store.session.space(id: targetSpace.id)?.tabs.first { $0.id == openedID }?.url,
            url
        )
        XCTAssertEqual(
            store.session.space(id: targetSpace.id)?.tabs.first { $0.id == openedID }?.placement,
            .current
        )
    }

    func testOpeningNewTabReusesTheSpacesUncommittedStartPageDraft() throws {
        let store = BrowserStore(session: .preview)
        let draft = try XCTUnwrap(store.selectedSpace?.currentTabs.first(where: \.isStartPage))
        let originalCount = try XCTUnwrap(store.selectedSpace).currentTabs.count

        let openedID = store.openNewTab()

        XCTAssertEqual(openedID, draft.id)
        XCTAssertEqual(store.selectedTab?.id, draft.id)
        XCTAssertEqual(try XCTUnwrap(store.selectedSpace).currentTabs.count, originalCount)
    }

    func testUpdatingSpaceBrowsingPreferencesPersistsOnlyThatSpacesChoices() async throws {
        let syncPersistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: syncPersistence,
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        )
        try coordinator.stage(session: .preview)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let store = BrowserStore(
            session: .preview,
            syncCoordinator: coordinator
        )
        let selectedSpaceID = store.selectedSpaceID
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
        let recordID = BrowserSyncRecordID(
            kind: .space,
            value: selectedSpaceID.rawValue
        )
        XCTAssertTrue(coordinator.journal.pendingRecordIDs.contains(recordID))
    }

    func testNormalStoreMutationStagesAndPersistsTheLocalSyncJournal() async throws {
        let syncPersistence = InMemoryBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: syncPersistence,
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        try coordinator.stage(session: .preview)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let store = BrowserStore(
            session: .preview,
            syncCoordinator: coordinator
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
        let visitedAt = Date(timeIntervalSince1970: 100)
        session.spaces[0].history = [
            BrowserHistoryEntry(
                url: try XCTUnwrap(URL(string: "https://example.com/private")),
                title: "Private",
                firstVisitedAt: visitedAt,
                lastVisitedAt: visitedAt
            )
        ]
        let historyID = try XCTUnwrap(session.spaces[0].history.first?.id)
        let coordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
        try coordinator.stage(session: session)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let store = BrowserStore(
            session: session,
            syncCoordinator: coordinator
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
            syncCoordinator: coordinator
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

    func testDeletingAPinnedTabStagesItsExplicitTombstoneAndArchiveAudit() async throws {
        let session = BrowserSession.preview
        let pinnedTab = try XCTUnwrap(session.spaces[0].pinnedTabs.first)
        let coordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: UUID(
                uuid: (
                    0x44, 0x45, 0x4C, 0x45, 0x54, 0x45, 0x41, 0x55,
                    0x44, 0x49, 0x54, 0x00, 0x00, 0x00, 0x00, 0x01
                )
            )
        )
        try coordinator.stage(session: session)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let store = BrowserStore(
            session: session,
            syncCoordinator: coordinator
        )

        store.deleteTab(pinnedTab.id, in: session.spaces[0].id)
        await store.flushPendingSyncPersistence()

        XCTAssertEqual(
            store.selectedSpace?.archivedTabs.first {
                $0.id == pinnedTab.id
            }?.reason,
            .deleted
        )
        let tabRecordID = BrowserSyncRecordID(
            kind: .tab,
            value: pinnedTab.id.rawValue
        )
        XCTAssertEqual(
            coordinator.journal.records.first { $0.id == tabRecordID }?
                .tombstone?.reason,
            .explicitDelete
        )
        let archiveRecord = try XCTUnwrap(
            coordinator.journal.records.first {
                $0.id
                    == BrowserSyncRecordID(
                        kind: .archive,
                        value: pinnedTab.id.rawValue
                    )
            }
        )
        guard case .archive(let archive)? = archiveRecord.payload else {
            return XCTFail("Expected deletion archive payload")
        }
        XCTAssertEqual(archive.reason, .deleted)
    }

    func testModifiedLinkOpensImmediatelyBelowItsOriginTab() throws {
        let store = BrowserStore(
            session: .preview
        )
        let spaceID = store.selectedSpaceID
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

        let memberTabIDs = try XCTUnwrap(store.selectedSpace).currentTabs.map(\.id)
        let originIndex = try XCTUnwrap(memberTabIDs.firstIndex(of: originID))
        XCTAssertEqual(memberTabIDs.index(after: originIndex), memberTabIDs.firstIndex(of: openedID))
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
            tabs: [pinned, current, draft]
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space])
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
            tabs: tabs
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
            tabs: [untouchedTab]
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [selectedSpace, untouchedSpace]),
            showing: selectedSpace.id, tabs: [selectedSpace.id: tabs[0].id, untouchedSpace.id: untouchedTab.id]
        )

        XCTAssertEqual(store.selectAdjacentTab(offset: -1), tabs[2].id)
        XCTAssertEqual(store.selectedTab?.id, tabs[2].id)
        XCTAssertEqual(store.selectAdjacentTab(offset: 1), tabs[0].id)
        XCTAssertEqual(store.selectedTab?.id, tabs[0].id)
        XCTAssertEqual(
            store.selectedTabID(in: untouchedSpace.id),
            untouchedTab.id
        )
    }

    func testFocusedWindowTabArchivePreservesAnotherWindowsSpaceSelection() throws {
        let root = BrowserStore(
            session: .preview
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
            tabs: [source, other]
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space]),
            showing: space.id, tabs: [space.id: source.id]
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
            tabs: [draft]
        )
        let store = BrowserStore(
            session: BrowserSession(spaces: [space])
        )

        XCTAssertNil(store.duplicateSelectedTab())
        XCTAssertEqual(store.selectedSpace?.tabs, [draft])
        XCTAssertEqual(store.selectedTab?.id, draft.id)
    }

    func testRapidSelectionChangesCoalesceSyncStagingToTheLatestSession() async throws {
        let syncPersistence = CountingBrowserSyncJournalPersistence()
        let coordinator = BrowserSyncCoordinator(
            persistence: syncPersistence,
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        )
        try coordinator.stage(session: .preview)
        let store = BrowserStore(
            session: .preview,
            syncCoordinator: coordinator
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

    func testProductionCompositionDoesNotBlockMainActorOnInitialSyncJournalSave() async {
        let syncPersistence = DelayedBrowserSyncJournalPersistence(delay: 0.4)
        let start = ContinuousClock.now

        let store = BrowserStore(
            session: .preview, syncCoordinator: BrowserSyncCoordinator(persistence: syncPersistence))
        let elapsed = start.duration(to: .now)

        XCTAssertLessThan(
            elapsed,
            .milliseconds(150),
            "Initial sync staging must not hold the main actor during cold launch."
        )
        let recordsStart = ContinuousClock.now
        let records = await store.cloudSyncRecords()
        let recordsElapsed = recordsStart.duration(to: .now)

        XCTAssertGreaterThanOrEqual(
            recordsElapsed,
            .milliseconds(250),
            "Cloud sync must wait for the initial local snapshot instead of racing it."
        )
        XCTAssertFalse(records.isEmpty)
        await store.flushPendingSyncPersistence()
    }

    func testDeletingASpacePurgesCredentialsAndStagesExplicitSyncTombstones() async throws {
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
            credentialVault: vault,
            syncCoordinator: coordinator
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
        XCTAssertEqual(store.selectedSpaceID, retainedSpace.id)
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
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            session: .preview,
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
        XCTAssertEqual(store.deletingSpaceIDs, [deletedSpace.id])
        XCTAssertEqual(store.session.spaceDeletions?.first?.profileID, deletedSpace.profile.id)
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
        let store = BrowserStore(
            session: session
        )
        let deleter = RecordingSpaceDataDeleter()

        await assertThrowsErrorAsync(
            expected: BrowserSpaceDeletionError.cannotDeleteLastSpace
        ) {
            try await store.deleteSpace(
                session.spaces[0].id,
                dataDeleter: deleter
            )
        }

        XCTAssertTrue(deleter.deletedSpaces.isEmpty)
        XCTAssertEqual(store.session.spaces.count, 1)
    }

    func testOpeningATabInASpaceBeingDeletedIsRefusedWithoutChangingSelection() async throws {
        let originalSession = BrowserSession.preview
        let store = BrowserStore(
            session: originalSession
        )
        let destination = try XCTUnwrap(
            store.session.spaces.first {
                $0.id != store.selectedSpaceID
            }
        )
        let sourceSpaceID = store.selectedSpaceID
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
        let sessionBeforeOpening = store.session

        XCTAssertTrue(store.deletingSpaceIDs.contains(destination.id))
        XCTAssertNil(
            store.openNewTab(
                url: try XCTUnwrap(URL(string: "https://deleting.crest.test")),
                in: destination.id,
                selecting: true
            )
        )
        XCTAssertEqual(store.selectedSpaceID, sourceSpaceID)
        XCTAssertEqual(
            store.session.space(id: sourceSpaceID)?.tabs.count,
            sourceTabCount
        )
        XCTAssertEqual(
            store.session.space(id: destination.id)?.tabs.count,
            destinationTabCount
        )
        XCTAssertEqual(store.session, sessionBeforeOpening)

        deleter.finishDeletion()
        try await deletion.value
        XCTAssertNil(store.session.space(id: destination.id))
    }

    func testMovingATabIntoASpaceBeingDeletedIsRefusedWithoutChangingEitherSpace() async throws {
        let store = BrowserStore(
            session: .preview,
            browsingMode: .privateBrowsing
        )
        let source = try XCTUnwrap(store.selectedSpace)
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
            savedTabsExpansionModifiedAt: source.savedTabsExpansionModifiedAt
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

    func testWindowStateStorePersistsChromeOnlyForItsOwningWindow() {
        let browser = BrowserStore(session: .preview)
        let layouts = BrowserWindowLayouts(defaults: nil)
        let firstWindow = BrowserWindowStateStore(id: BrowserWindowID(), browser: browser, layouts: layouts)
        let secondWindow = BrowserWindowStateStore(id: BrowserWindowID(), browser: browser, layouts: layouts)

        firstWindow.captureSidebar(width: 364, isPresented: false)
        secondWindow.captureSidebar(width: 278, isPresented: true)

        XCTAssertEqual(layouts.layout(for: firstWindow.id)?.sidebarWidth, 364)
        XCTAssertEqual(layouts.layout(for: firstWindow.id)?.sidebarIsPresented, false)
        XCTAssertEqual(layouts.layout(for: secondWindow.id)?.sidebarWidth, 278)
        XCTAssertEqual(layouts.layout(for: secondWindow.id)?.sidebarIsPresented, true)
    }

    func testWindowStoresShareBrowserMutationsButKeepIndependentSelections() throws {
        let firstWindow = BrowserStore(session: .preview)
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

    func testDelayedStageFromAnotherWindowCannotDeleteANewerPinnedTab() async throws {
        let session = BrowserSession.preview
        let coordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence(),
            deviceID: UUID(
                uuid: (
                    0x4D, 0x55, 0x4C, 0x54, 0x49, 0x57, 0x49, 0x4E,
                    0x44, 0x4F, 0x57, 0x53, 0x00, 0x00, 0x00, 0x01
                )
            )
        )
        try coordinator.stage(session: session)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        let firstWindow = BrowserStore(
            session: session,
            syncCoordinator: coordinator
        )
        let secondWindow = firstWindow.makeWindowStore()
        let existingTab = try XCTUnwrap(secondWindow.selectedTab)

        XCTAssertTrue(
            secondWindow.setTabCustomTitle(
                "Queued before the pinned tab",
                for: existingTab.id,
                in: secondWindow.selectedSpaceID
            )
        )
        let pinnedTabID = try XCTUnwrap(
            firstWindow.openSessionTab(
                .page(try XCTUnwrap(URL(string: "https://pinned.crest.test")), title: "Pinned"),
                in: firstWindow.selectedSpaceID, placement: .pinned, shouldSelect: false
            )
        )

        await firstWindow.flushPendingSyncPersistence()
        await secondWindow.flushPendingSyncPersistence()

        let recordID = BrowserSyncRecordID(
            kind: .tab,
            value: pinnedTabID.rawValue
        )
        let record = try XCTUnwrap(
            coordinator.journal.records.first { $0.id == recordID }
        )
        XCTAssertNotNil(record.payload)
        XCTAssertNil(record.tombstone)
        XCTAssertTrue(
            try coordinator.journal
                .materializedSession(applyingTo: firstWindow.session)
                .space(id: firstWindow.selectedSpaceID)?
                .tabs.contains(where: { $0.id == pinnedTabID }) == true
        )
    }

    func testIncomingSyncPreservesCustomizationWaitingForCoalescedPersistence() async throws {
        let session = BrowserSession.preview
        let coordinator = BrowserSyncCoordinator(persistence: InMemoryBrowserSyncJournalPersistence())
        try coordinator.stage(session: session)
        try coordinator.markUploaded(coordinator.journal.pendingRecordIDs)
        var remote = BrowserSyncJournal()
        try remote.merge(coordinator.journal.records)
        var remoteSession = session
        let newTab = BrowserTab(title: "Cloud page", url: URL(string: "http://localhost:3000"), placement: .current)
        remoteSession.spaces[0].tabs.append(newTab)
        try remote.stage(session: remoteSession)

        let store = BrowserStore(
            session: session, syncCoordinator: coordinator)
        let otherWindow = store.makeWindowStore()
        let spaceID = session.spaces[0].id
        var branding = session.spaces[0].branding
        branding.iconStyle = .layeredCrest
        branding.crest.symbol = .direwolf
        branding.crest.palette = [.ink, .gold, .ocean]
        otherWindow.updateSpaceBranding(branding, in: spaceID)

        // The receiving window must retain an edit from another window before
        // invalidating its delayed stage to apply this CloudKit batch.
        try store.mergeRemoteSyncRecords(remote.records)
        await otherWindow.flushPendingSyncPersistence()

        XCTAssertEqual(store.session.space(id: spaceID)?.branding, branding)
        XCTAssertEqual(otherWindow.session.space(id: spaceID)?.branding, branding)
        XCTAssertTrue(store.session.spaces[0].tabs.contains { $0.id == newTab.id })
        let spaceRecordID = BrowserSyncRecordID(kind: .space, value: spaceID.rawValue)
        XCTAssertTrue(coordinator.journal.pendingRecordIDs.contains(spaceRecordID))
        try remote.merge(coordinator.journal.records)
        XCTAssertEqual(
            try remote.materializedSession(applyingTo: remoteSession).space(id: spaceID)?.branding,
            branding)
    }

    func testSceneActivationSweepArchivesExpiredCurrentTabsInALongLivedSession() throws {
        let now = Date.now
        let fixture = Self.makeCleanupSweepFixture(now: now)
        let store = BrowserStore(session: fixture.session)

        // Only launch and explicit actions used to sweep, so a store that is
        // already running still holds the expired tab before activation.
        let beforeSweep = try XCTUnwrap(store.session.space(id: fixture.sweepingSpaceID))
        XCTAssertTrue(beforeSweep.contains(fixture.expiredTabID))
        XCTAssertTrue(beforeSweep.archivedTabs.isEmpty)

        store.sweepExpiredBrowsingData()

        let swept = try XCTUnwrap(store.session.space(id: fixture.sweepingSpaceID))
        XCTAssertFalse(swept.contains(fixture.expiredTabID))
        XCTAssertEqual(swept.archivedTabs.map(\.id), [fixture.expiredTabID])
        XCTAssertEqual(swept.archivedTabs.first?.reason, .autoCleanup)
        XCTAssertEqual(try XCTUnwrap(swept.archivedTabs.first?.archivedAt).timeIntervalSince(now), 0, accuracy: 60)
        // The stale selected tab and the start page stay put.
        XCTAssertTrue(swept.contains(fixture.selectedTabID))
        XCTAssertEqual(store.selectedTabID(in: fixture.sweepingSpaceID), fixture.selectedTabID)
        XCTAssertTrue(swept.contains(fixture.startPageID))
    }

    func testSceneActivationSweepRespectsEverySpaceCleanupPolicy() throws {
        let fixture = Self.makeCleanupSweepFixture(now: .now)
        let store = BrowserStore(
            session: fixture.session
        )

        store.sweepExpiredBrowsingData()

        let neverSpace = try XCTUnwrap(store.session.space(id: fixture.neverSpaceID))
        XCTAssertTrue(neverSpace.contains(fixture.neverPolicyTabID))
        XCTAssertTrue(neverSpace.archivedTabs.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(store.session.space(id: fixture.sweepingSpaceID)).archivedTabs.count,
            1
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
            )
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
            )
        )
        return CleanupSweepFixture(
            session: BrowserSession(spaces: [sweepingSpace, neverSpace]),
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

private final class DelayedBrowserSyncJournalPersistence: BrowserSyncJournalPersisting {
    private let delay: TimeInterval
    private var journal: BrowserSyncJournal?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func load() throws -> BrowserSyncJournal? {
        journal
    }

    func save(_ journal: BrowserSyncJournal) throws {
        Thread.sleep(forTimeInterval: delay)
        self.journal = journal
    }
}

/// What page observations, history and organization edits change in the
/// shared session, how often they stage sync, and what they refuse.
@MainActor
final class BrowserStoreMutationTests: XCTestCase {

    /// A web page's address and title stay the page's own until its engine
    /// reports the navigation, which the core records.
    func testSelectedPageKeepsProvisionalMetadataVisual() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://example.com/old"))
        let nextURL = try XCTUnwrap(URL(string: "https://example.com/new"))
        let tab = BrowserTab(title: "Old", url: originalURL, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Test", symbol: "circle",
            accent: .indigo, folders: [], tabs: [tab])
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space]))
        let synchronizer = BrowserPageSessionSynchronizer(
            browser: browser, spaceAccess: BrowserSpaceAccessController())
        let source = BrowserTabRuntimeAssignment(
            tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        let metadata = BrowserPageMetadata(
            url: nextURL, displayURL: nextURL, title: "New", displayTitle: "New",
            faviconData: Data("new icon".utf8), iconAccent: nil)

        browser.navigateSelectedTab(to: nextURL)
        XCTAssertEqual(synchronizer.address(of: metadata, matching: source), nextURL.absoluteString)
        XCTAssertEqual(browser.selectedTab?.url, originalURL)
        XCTAssertEqual(browser.selectedTab?.title, "Old")
        XCTAssertTrue(try XCTUnwrap(browser.selectedSpace).history.isEmpty)
    }

    func testClearingHistoryEmptiesOnlyTheSelectedSpace() throws {
        let store = BrowserStore(session: .preview)
        let selectedSpaceID = store.selectedSpaceID
        store.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/read")),
            titled: "Read"
        )

        store.clearHistory()

        XCTAssertTrue(try XCTUnwrap(store.session.space(id: selectedSpaceID)?.history.isEmpty))
    }

    func testClearingCapturedSpaceHistoryDoesNotRetargetAfterSelectionChanges() throws {
        let store = BrowserStore(session: .preview)
        let initiatingSpace = try XCTUnwrap(store.selectedSpace)
        let laterSelectedSpace = try XCTUnwrap(
            store.session.spaces.first { $0.id != initiatingSpace.id }
        )
        let request = BrowserSidebarClearHistoryConfirmation(
            assignment: BrowserSpaceRuntimeAssignment(space: initiatingSpace),
            spaceName: initiatingSpace.name
        )
        store.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/initiating")),
            titled: "Initiating"
        )
        store.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/later-selected")),
            titled: "Later selected",
            in: laterSelectedSpace.id
        )

        store.selectSpace(laterSelectedSpace.id)
        XCTAssertTrue(store.clearHistory(matching: request.assignment))

        XCTAssertEqual(store.selectedSpaceID, laterSelectedSpace.id)
        XCTAssertTrue(
            try XCTUnwrap(store.session.space(id: initiatingSpace.id))
                .history.isEmpty
        )
        XCTAssertEqual(
            try XCTUnwrap(store.session.space(id: laterSelectedSpace.id))
                .history.count,
            1
        )
    }

    func testClearingCapturedHistoryRejectsAReplacementBrowsingProfile() throws {
        let store = BrowserStore(
            session: .preview,
            browsingMode: .privateBrowsing
        )
        let initiatingSpace = try XCTUnwrap(store.selectedSpace)
        store.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/private")),
            titled: "Private"
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
                currentSpace.savedTabsExpansionModifiedAt
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
            savedTabsExpansionModifiedAt: original.savedTabsExpansionModifiedAt
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

    func testSavedTabsAndFolderDisclosureChangeTheirSpace() throws {
        let store = BrowserStore(session: .preview)
        let spaceID = try XCTUnwrap(store.selectedSpace?.id)
        let folderID = try XCTUnwrap(store.selectedSpace?.folders.first?.id)

        XCTAssertTrue(store.setSavedTabsExpanded(false, in: spaceID))
        XCTAssertEqual(store.selectedSpace?.isSavedTabsExpanded, false)

        XCTAssertTrue(
            store.setFolderCollapsed(folderID, in: spaceID, isCollapsed: true)
        )
        XCTAssertEqual(
            store.selectedSpace?.folders.first { $0.id == folderID }?.isCollapsed,
            true
        )
    }
}
