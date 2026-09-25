import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserStoreWorkspaceTests: XCTestCase {
    func testAnEmptyWindowSelectionSurvivesOtherWindowsPublishingAndDeletingTabs() throws {
        let first = BrowserStore(session: .preview, core: .hostingPages())
        let empty = first.makeWindowStore(BrowserWindowOpening(restoresTabs: false))
        let tab = try XCTUnwrap(first.selectedSpace?.tabs.first)
        let ids = first.session.tabIDs

        first.seedSelectedTabNavigation(to: tab.url, titled: "Changed elsewhere")

        XCTAssertNil(empty.selectedTab)
        XCTAssertEqual(empty.session.tabIDs, ids)
        first.deleteTab(tab.id, in: first.selectedSpaceID)
        XCTAssertNil(empty.selectedTab)
        XCTAssertFalse(empty.session.tabIDs.contains(tab.id))
    }

    func testTemporaryWorkspaceBorrowsItsProfileButKeepsAllBrowsingRecordsLocal() async throws {
        let harness = try BrowserStoredSessionHarness(session: .preview)
        harness.core.engines.register(WebKitEngineBinding(), isDefault: true)
        let source = harness.store
        let sourceSpace = try XCTUnwrap(source.selectedSpace)
        let original = source.session
        let temporary = try XCTUnwrap(
            source.makeTemporaryWindowStore(in: BrowserSpaceRuntimeAssignment(space: sourceSpace)))

        XCTAssertTrue(temporary.isTemporaryWorkspace)
        XCTAssertFalse(temporary.family === source.family)
        XCTAssertFalse(temporary.syncsSession)
        XCTAssertEqual(temporary.selectedSpace?.profile, sourceSpace.profile)
        XCTAssertEqual(temporary.selectedSpace?.browsingPreferences, sourceSpace.browsingPreferences)
        XCTAssertEqual(temporary.selectedSpace?.credentialPreferences, sourceSpace.credentialPreferences)
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).tabs.isEmpty)
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).folders.isEmpty)
        XCTAssertNil(temporary.selectedTab)

        let url = try XCTUnwrap(URL(string: "https://temporary.crest.test/local"))
        let tabID = try XCTUnwrap(temporary.openNewTab(url: url))
        let page = try XCTUnwrap(temporary.openReportingPage(for: nil))
        temporary.finishNavigation(of: page, to: url, titled: "Temporary visit")
        page.release(keepingState: false)
        temporary.pinTab(tabID)
        temporary.deleteTab(tabID, in: sourceSpace.id)

        XCTAssertEqual(source.session, original)
        XCTAssertEqual(temporary.selectedSpace?.history.first?.url, url)
        XCTAssertEqual(temporary.selectedSpace?.archivedTabs.first?.id, tabID)
        // Nothing the temporary workspace did reaches its source's file.
        await temporary.flushPendingSyncPersistence()
        await source.flushPendingSyncPersistence()
        XCTAssertEqual(try harness.stored().session, original)
    }

    func testTemporaryWorkspaceFollowsItsSourceKeepingLocalOrganizationAndClosesOnAReplacedProfile() throws {
        let source = BrowserStore(session: .preview)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(source.selectedSpace))
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let url = try XCTUnwrap(URL(string: "https://temporary.crest.test/keep"))
        let tabID = try XCTUnwrap(temporary.openNewTab(url: url))
        let folderID = try XCTUnwrap(temporary.addFolder(title: "Local folder", in: assignment.spaceID))
        temporary.pinTab(tabID)
        // The source's edit reaches the temporary workspace with the edit itself.
        source.updateSpaceIdentity(assignment.spaceID, name: "Source renamed", symbol: "book", accent: .orange)

        XCTAssertTrue(temporary.family.isOpen)
        XCTAssertEqual(temporary.selectedSpace?.name, "Source renamed")
        XCTAssertEqual(temporary.selectedSpace?.tabs.map(\.id), [tabID])
        XCTAssertEqual(temporary.selectedSpace?.pinnedTabs.map(\.id), [tabID])
        XCTAssertEqual(temporary.selectedSpace?.folders.map(\.id), [folderID])
        let before = temporary.session
        // A replacement of the Space's profile, as only the cloud makes, closes it.
        source.replaceProfileForTesting(of: assignment.spaceID)
        XCTAssertFalse(temporary.family.isOpen)
        XCTAssertTrue(temporary.session.spaces.isEmpty)
        // Revocation hides access, but must not rewrite the local browsing records.
        XCTAssertEqual(temporary.family.authoritativeSession, before)
    }

    func testTemporaryProfileSettingsUseTheSourceAuthorityImmediately() throws {
        let source = BrowserStore(session: .preview)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(source.selectedSpace))
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let originalTabs = source.session.tabIDs
        XCTAssertTrue(temporary.profileSettingsBrowser.family === source.family)
        XCTAssertFalse(temporary.profileSettingsBrowser === source)
        temporary.addSpace()
        XCTAssertEqual(temporary.session.spaces.map(\.id), [assignment.spaceID])

        temporary.updateSpaceIdentity(assignment.spaceID, name: "Canonical rename", symbol: "book", accent: .orange)
        var preferences = try XCTUnwrap(temporary.selectedSpace).browsingPreferences
        preferences.searchProvider = .duckDuckGo
        temporary.updateBrowsingPreferences(preferences, in: assignment.spaceID)
        // Asking for authentication locks the Space, which this process has
        // not unlocked, so it comes last.
        temporary.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: assignment.spaceID)

        XCTAssertEqual(source.selectedSpace?.name, "Canonical rename")
        XCTAssertEqual(source.selectedSpace?.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertEqual(source.selectedSpace?.browsingPreferences.searchProvider, .duckDuckGo)
        XCTAssertEqual(source.session.tabIDs, originalTabs)
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).tabs.isEmpty)
        XCTAssertTrue(source.family.beginDeletingSpace(assignment.spaceID))
        XCTAssertNil(temporary.selectedSpace)
        XCTAssertNil(temporary.space(matching: assignment))
        source.family.finishDeletingSpace(assignment.spaceID)
    }

    func testTemporaryWorkspaceCannotDeleteItsBorrowedProfile() async throws {
        let source = BrowserStore(session: .preview)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(source.selectedSpace))
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let deleter = WorkspaceDataDeleter()
        let before = source.session

        do {
            try await temporary.deleteSpace(assignment.spaceID, dataDeleter: deleter)
            XCTFail("The workspace must not delete its borrowed profile")
        } catch {
            XCTAssertEqual(
                error as? Rejection,
                .borrowedProfileRequiresOwner(BorrowedProfileRequiresOwner(workspaceID: temporary.family.workspaceID)))
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
            folders: [folder], tabs: [tab])
        let companionTab = BrowserTab(
            title: "Other Space", url: URL(string: "https://transfer.crest.test/other"), placement: .current)
        let companion = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Companion", symbol: "globe", accent: .orange,
            folders: [], tabs: [companionTab])
        let source = BrowserStore(
            session: BrowserSession(spaces: [space, companion]),
            showing: space.id, tabs: [space.id: tab.id, companion.id: companionTab.id])
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
        XCTAssertNil(source.selectedTab)
        XCTAssertTrue(try XCTUnwrap(source.selectedSpace).tabs.isEmpty)

        XCTAssertTrue(temporary.transferTab(tab.id, matching: assignment, to: source, in: assignment))
        XCTAssertEqual(source.selectedTab?.id, tab.id)
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).tabs.isEmpty)
        XCTAssertNil(temporary.selectedTab)
        XCTAssertTrue(try XCTUnwrap(temporary.selectedSpace).archivedTabs.isEmpty)
    }

    func testTransferRejectsStaleAssignmentsAtomically() throws {
        let source = BrowserStore(session: .preview)
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
    }

}

@MainActor
private final class WorkspaceDataDeleter: BrowserSpaceDataDeleting {
    var wasCalled = false

    func deleteData(for space: BrowserSpace) async throws {
        wasCalled = true
    }
}
