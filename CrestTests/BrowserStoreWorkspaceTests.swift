import Foundation
import Observation
import XCTest

@testable import Crest

@MainActor
final class BrowserStoreWorkspaceTests: XCTestCase {
    func testWindowStoresReadTheSameMutationBeforePersistenceAndKeepTheirOwnSelection() throws {
        let first = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let second = first.makeWindowStore()
        let space = try XCTUnwrap(first.selectedSpace)
        let firstTab = space.tabs[0]
        let secondTab = space.tabs[1]
        first.selectTab(firstTab.id)
        second.selectTab(secondTab.id)

        first.session.updateTab(url: firstTab.url, title: "Shared immediately", tabID: firstTab.id, in: space.id)

        XCTAssertEqual(
            second.session.space(id: space.id)?.tabs.first { $0.id == firstTab.id }?.title, "Shared immediately")
        second.session.updateSpaceIdentity(
            space.id, name: "Renamed from another window", symbol: space.symbol, accent: space.accent)
        XCTAssertEqual(first.selectedSpace?.name, "Renamed from another window")
        XCTAssertEqual(first.selectedTab?.id, firstTab.id)
        XCTAssertEqual(second.selectedTab?.id, secondTab.id)
        XCTAssertEqual(
            first.session.space(id: space.id)?.tabs.first { $0.id == firstTab.id }?.title, "Shared immediately")
    }

    func testAnEmptyWindowSelectionSurvivesOtherWindowsPublishingAndDeletingTabs() throws {
        let first = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let empty = first.makeWindowStore(restoresTabSelection: false)
        let tab = try XCTUnwrap(first.selectedSpace?.tabs.first)
        let ids = first.session.tabIDs

        first.updateSelectedTabFromPage(url: tab.url, title: "Changed elsewhere")

        XCTAssertNil(empty.selectedTab)
        XCTAssertEqual(empty.session.tabIDs, ids)
        first.deleteTab(tab.id, in: first.session.selectedSpaceID)
        XCTAssertNil(empty.selectedTab)
        XCTAssertFalse(empty.session.tabIDs.contains(tab.id))
    }

    func testAWindowObservesSharedMetadataAndItsOwnSelectionChanges() throws {
        let first = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let second = first.makeWindowStore()
        let tab = try XCTUnwrap(second.selectedTab)
        let observed = expectation(description: "Shared metadata invalidates the other window")
        withObservationTracking {
            _ = second.selectedTab?.title
        } onChange: {
            observed.fulfill()
        }

        first.session.updateTab(
            url: tab.url, title: "Observed shared title", tabID: tab.id, in: second.session.selectedSpaceID)

        wait(for: [observed], timeout: 1)
        XCTAssertEqual(second.selectedTab?.title, "Observed shared title")
        let selectionChanged = expectation(description: "Local selection invalidates the window")
        withObservationTracking {
            _ = second.selectedTab
        } onChange: {
            selectionChanged.fulfill()
        }
        second.session.spaces[0].selectedTabID = nil
        wait(for: [selectionChanged], timeout: 1)
        XCTAssertNil(second.selectedTab)
        XCTAssertEqual(first.selectedTab?.id, tab.id)
    }

    func testAnExplicitEmptyWindowSelectionSurvivesPersistenceAndRestoration() throws {
        let owner = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let empty = owner.makeWindowStore(restoresTabSelection: false)
        let captured = BrowserWindowState(restoring: empty.session)
        var saved = try JSONDecoder().decode(BrowserWindowState.self, from: JSONEncoder().encode(captured))
        saved.repair(using: owner.session)

        let restored = owner.makeWindowStore(restoring: saved)

        XCTAssertNil(saved.selectedTab(in: owner.session))
        XCTAssertNil(restored.selectedTab)
        XCTAssertTrue(restored.session.spaces.allSatisfy { $0.selectedTabID == nil })
        XCTAssertEqual(restored.session.tabIDs, owner.session.tabIDs)

        var legacy = BrowserWindowState(selectedSpaceID: owner.session.selectedSpaceID, selectedTabIDsBySpace: [:])
        legacy.repair(using: owner.session)
        XCTAssertEqual(legacy.selectedTab(in: owner.session)?.id, owner.selectedTab?.id)
    }

    func testTemporaryWorkspaceBorrowsItsProfileButKeepsAllBrowsingRecordsLocal() throws {
        let persistence = InMemoryBrowserSessionPersistence()
        let source = BrowserStore(session: .preview, persistence: persistence)
        let sourceSpace = try XCTUnwrap(source.selectedSpace)
        let original = source.session
        let temporary = try XCTUnwrap(
            source.makeTemporaryWindowStore(in: BrowserSpaceRuntimeAssignment(space: sourceSpace)))

        XCTAssertTrue(temporary.isTemporaryWorkspace)
        XCTAssertFalse(temporary.family === source.family)
        XCTAssertNil(temporary.syncCoordinator)
        XCTAssertTrue(temporary.persistence is InMemoryBrowserSessionPersistence)
        XCTAssertEqual(temporary.selectedSpace?.profile, sourceSpace.profile)
        XCTAssertEqual(temporary.selectedSpace?.browsingPreferences, sourceSpace.browsingPreferences)
        XCTAssertEqual(temporary.selectedSpace?.credentialPreferences, sourceSpace.credentialPreferences)
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).tabs.isEmpty)
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).folders.isEmpty)
        XCTAssertNil(temporary.selectedTab)

        let url = try XCTUnwrap(URL(string: "https://temporary.crest.test/local"))
        let tabID = try XCTUnwrap(temporary.openNewTab(url: url))
        temporary.recordVisit(url: url, title: "Temporary visit")
        temporary.pinTab(tabID)
        temporary.deleteTab(tabID, in: sourceSpace.id)

        XCTAssertEqual(source.session, original)
        XCTAssertTrue(persistence.savedScopes.isEmpty)
        XCTAssertEqual(temporary.selectedSpace?.history.first?.url, url)
        XCTAssertEqual(temporary.selectedSpace?.archivedTabs.first?.id, tabID)
        XCTAssertEqual(temporary.persistence.load(), temporary.session)
    }

    func testTemporarySourceRefreshKeepsLocalOrganizationAndRejectsReplacedProfiles() throws {
        let source = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(source.selectedSpace))
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let url = try XCTUnwrap(URL(string: "https://temporary.crest.test/keep"))
        let tabID = try XCTUnwrap(temporary.openNewTab(url: url))
        let folderID = try XCTUnwrap(temporary.session.addFolder(title: "Local folder", in: assignment.spaceID))
        temporary.pinTab(tabID)
        source.updateSpaceIdentity(assignment.spaceID, name: "Source renamed", symbol: "book", accent: .orange)

        XCTAssertTrue(temporary.reconcileTemporarySource(from: source.session))
        XCTAssertEqual(temporary.selectedSpace?.name, "Source renamed")
        XCTAssertEqual(temporary.selectedSpace?.tabs.map(\.id), [tabID])
        XCTAssertEqual(temporary.selectedSpace?.pinnedTabs.map(\.id), [tabID])
        XCTAssertEqual(temporary.selectedSpace?.folders.map(\.id), [folderID])
        let before = temporary.session
        var replacement = source.session
        replacement.spaces[0] = BrowserSpace(
            id: assignment.spaceID, profile: BrowsingProfile(), name: "Replacement", symbol: "globe", accent: .indigo,
            folders: [], tabs: [], selectedTabID: nil)
        XCTAssertFalse(temporary.reconcileTemporarySource(from: replacement))
        XCTAssertEqual(temporary.session, before)
        replacement.spaces.removeAll()
        XCTAssertFalse(temporary.reconcileTemporarySource(from: replacement))
        XCTAssertEqual(temporary.session, before)
    }

    func testTemporaryProfileSettingsUseTheSourceAuthorityImmediately() throws {
        let source = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(source.selectedSpace))
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let originalTabs = source.session.tabIDs
        XCTAssertTrue(temporary.profileSettingsBrowser.family === source.family)
        XCTAssertFalse(temporary.profileSettingsBrowser === source)
        temporary.addSpace()
        XCTAssertEqual(temporary.session.spaces.map(\.id), [assignment.spaceID])

        source.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: assignment.spaceID)
        XCTAssertEqual(temporary.selectedSpace?.accessPolicy, .deviceOwnerAuthentication)
        temporary.updateSpaceIdentity(assignment.spaceID, name: "Canonical rename", symbol: "book", accent: .orange)
        temporary.updateSpaceAccessPolicy(.open, in: assignment.spaceID)
        var preferences = try XCTUnwrap(temporary.selectedSpace).browsingPreferences
        preferences.searchProvider = .duckDuckGo
        temporary.updateBrowsingPreferences(preferences, in: assignment.spaceID)

        XCTAssertEqual(source.selectedSpace?.name, "Canonical rename")
        XCTAssertEqual(source.selectedSpace?.accessPolicy, .open)
        XCTAssertEqual(source.selectedSpace?.browsingPreferences.searchProvider, .duckDuckGo)
        XCTAssertEqual(source.session.tabIDs, originalTabs)
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).tabs.isEmpty)
        XCTAssertTrue(source.family.beginDeletingSpace(assignment.spaceID))
        XCTAssertNil(temporary.selectedSpace)
        XCTAssertNil(temporary.space(matching: assignment))
        source.family.finishDeletingSpace(assignment.spaceID)
    }

    func testTemporaryWorkspaceCannotDeleteItsBorrowedProfile() async throws {
        let source = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(source.selectedSpace))
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let deleter = WorkspaceDataDeleter()
        let before = source.session

        do {
            try await temporary.deleteSpace(assignment.spaceID, dataDeleter: deleter)
            XCTFail("The workspace must not delete its borrowed profile")
        } catch {
            XCTAssertEqual(error as? BrowserSpaceDeletionError, .borrowedProfile)
        }
        XCTAssertFalse(deleter.wasCalled)
        XCTAssertEqual(source.session, before)
    }

    func testTransferMovesTheSameTabBetweenFamiliesWithoutArchivingOrFillingTheEmptySource() throws {
        let folder = BrowserFolder(title: "Source folder", symbol: "folder")
        let tab = BrowserTab(
            title: "Move me", url: URL(string: "https://transfer.crest.test/live"),
            savedURL: URL(string: "https://transfer.crest.test/saved"),
            faviconData: Data("icon".utf8),
            placement: .saved, folderID: folder.id)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Source", symbol: "globe", accent: .indigo,
            folders: [folder], tabs: [tab], selectedTabID: tab.id)
        let companionTab = BrowserTab(
            title: "Other Space", url: URL(string: "https://transfer.crest.test/other"), placement: .current)
        let companion = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Companion", symbol: "globe", accent: .orange,
            folders: [], tabs: [companionTab], selectedTabID: companionTab.id)
        let source = BrowserStore(
            session: BrowserSession(spaces: [space, companion], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence())
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))

        XCTAssertTrue(source.canTransferTab(tab.id, matching: assignment, to: temporary, in: assignment))
        XCTAssertEqual(source.selectedSpace?.tabs.map(\.id), [tab.id])
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).tabs.isEmpty)
        XCTAssertTrue(source.transferTab(tab.id, matching: assignment, to: temporary, in: assignment))

        XCTAssertTrue(try XCTUnwrap(source.selectedSpace).tabs.isEmpty)
        XCTAssertNil(source.selectedTab)
        XCTAssertTrue(try XCTUnwrap(source.selectedSpace).archivedTabs.isEmpty)
        XCTAssertEqual(source.selectedSpace?.folders.map(\.id), [folder.id])
        XCTAssertEqual(temporary.selectedTab?.id, tab.id)
        XCTAssertEqual(temporary.selectedTab?.faviconData, tab.faviconData)
        XCTAssertEqual(temporary.selectedTab?.url, tab.url)
        XCTAssertEqual(temporary.selectedTab?.placement, .current)
        XCTAssertNil(temporary.selectedTab?.folderID)
        XCTAssertNil(temporary.selectedTab?.savedURL)
        _ = try source.extensionTabGroups.group([companionTab.id], in: companion.id, into: nil)
        source.persist(scope: .core)
        XCTAssertNil(source.selectedTab)
        XCTAssertTrue(try XCTUnwrap(source.selectedSpace).tabs.isEmpty)

        XCTAssertTrue(temporary.transferTab(tab.id, matching: assignment, to: source, in: assignment))
        XCTAssertEqual(source.selectedTab?.id, tab.id)
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).tabs.isEmpty)
        XCTAssertNil(temporary.selectedTab)
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).archivedTabs.isEmpty)
    }

    func testTransferRemovesSourceSplitReferencesWithoutArchivingEitherMember() throws {
        let groupID = SplitGroupID()
        let tab = BrowserTab(
            title: "Moving", url: URL(string: "https://transfer.crest.test/moving"), placement: .current,
            splitGroupID: groupID)
        let remaining = BrowserTab(
            title: "Remaining", url: URL(string: "https://transfer.crest.test/remaining"), placement: .current,
            splitGroupID: groupID)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Source", symbol: "globe", accent: .indigo,
            folders: [], tabs: [tab, remaining], selectedTabID: tab.id)
        let source = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence())
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        XCTAssertTrue(source.setSplitGroupTitle("Pair", groupID: groupID, matching: assignment))
        let destination = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))

        XCTAssertTrue(source.transferTab(tab.id, matching: assignment, to: destination, in: assignment))

        XCTAssertEqual(source.selectedSpace?.tabs.map(\.id), [remaining.id])
        XCTAssertNil(source.selectedSpace?.tabs.first?.splitGroupID)
        XCTAssertTrue(try XCTUnwrap(source.selectedSpace).splitGroups.isEmpty)
        XCTAssertTrue(try XCTUnwrap(source.selectedSpace).archivedTabs.isEmpty)
        XCTAssertNil(destination.selectedTab?.splitGroupID)
        XCTAssertTrue(try XCTUnwrap(destination.selectedSpace).splitGroups.isEmpty)
    }

    func testTransferRejectsStaleAssignmentsAndDuplicateDestinationIdentityAtomically() throws {
        let source = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let space = try XCTUnwrap(source.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let destination = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let stale = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: UUID())
        let beforeSource = source.session
        let beforeDestination = destination.session

        XCTAssertFalse(source.canTransferTab(tab.id, matching: stale, to: destination, in: assignment))
        XCTAssertFalse(source.canTransferTab(tab.id, matching: assignment, to: destination, in: stale))
        XCTAssertFalse(source.transferTab(tab.id, matching: stale, to: destination, in: assignment))
        XCTAssertFalse(source.transferTab(tab.id, matching: assignment, to: destination, in: stale))
        XCTAssertEqual(source.session, beforeSource)
        XCTAssertEqual(destination.session, beforeDestination)

        destination.session.spaces[0].tabs.append(tab)
        let duplicateDestination = destination.session
        XCTAssertFalse(source.canTransferTab(tab.id, matching: assignment, to: destination, in: assignment))
        XCTAssertFalse(source.transferTab(tab.id, matching: assignment, to: destination, in: assignment))
        XCTAssertEqual(source.session, beforeSource)
        XCTAssertEqual(destination.session, duplicateDestination)
    }

    func testTransferWithinTheSharedFamilyOnlyChangesTheDestinationWindowSelection() throws {
        let first = BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
        let second = first.makeWindowStore()
        let space = try XCTUnwrap(first.selectedSpace)
        let tab = try XCTUnwrap(space.tabs.first)
        let sourceSelection = first.selectedTab?.id
        let assignment = BrowserSpaceRuntimeAssignment(space: space)

        XCTAssertTrue(first.transferTab(tab.id, matching: assignment, to: second, in: assignment))

        XCTAssertEqual(first.selectedTab?.id, sourceSelection)
        XCTAssertEqual(second.selectedTab?.id, tab.id)
        XCTAssertTrue(first.session.tabIDs.contains(tab.id))
        XCTAssertEqual(first.session.tabIDs, second.session.tabIDs)
    }
}

@MainActor
private final class WorkspaceDataDeleter: BrowserSpaceDataDeleting {
    var wasCalled = false

    func deleteData(for space: BrowserSpace) async throws {
        wasCalled = true
    }
}
