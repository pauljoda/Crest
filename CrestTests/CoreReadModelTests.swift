import Foundation
import Observation
import XCTest

@testable import Crest

/// The read model the core's changes update. Fed the batches the core
/// drained, from the workspace's opening on, it holds what the Swift session
/// copy holds; a batch applied twice changes nothing; and a change notifies
/// only the objects whose values it really changes.
@MainActor
final class CoreReadModelTests: XCTestCase {
    func testTheReadModelFedTheDrainedBatchesHoldsWhatTheCopyHolds() throws {
        let core = CrestCore()
        var batches: [[Change]] = []
        core.batchApplied = { batches.append($0) }
        var original = BrowserSession.preview
        let icon = Data([7, 7, 7])
        original.spaces[0].tabs[0].faviconData = icon
        original.spaces[0].tabs[0].faviconURL = original.spaces[0].tabs[0].url
        let store = BrowserStore(session: original, core: core)
        let spaceID = original.spaces[0].id
        let first = original.spaces[0].tabs[0].id

        let opened = try XCTUnwrap(
            store.openSessionTab(title: "Opened", url: URL(string: "https://opened.example/"), in: spaceID))
        XCTAssertTrue(store.setTabCustomTitle("Renamed", for: opened, in: spaceID))
        let pulled = Data([1, 2, 3])
        store.setTabFavicon(pulled, iconAccent: nil, for: opened, in: spaceID)
        let copy = try XCTUnwrap(store.duplicateTab(opened, in: spaceID))
        store.recordVisit(url: try XCTUnwrap(URL(string: "https://visited.example/a")), title: "First")
        store.recordVisit(url: try XCTUnwrap(URL(string: "https://visited.example/a#again")), title: "Again")
        XCTAssertTrue(store.closeTab(opened, in: spaceID))
        store.restoreArchivedTab(opened)
        XCTAssertNotNil(
            store.addFolder(title: "Reading", matching: BrowserSpaceRuntimeAssignment(space: store.session.spaces[0])))
        store.selectTab(first)
        store.updateSpaceIdentity(spaceID, name: "Renamed Space", symbol: "book", accent: .teal)
        store.addSpace()

        // The images move with their tabs: the pulled image survives the
        // archive and the restore, and the copy wears its source's.
        XCTAssertEqual(core.state.favicons.image(of: first.rawValue), icon)
        XCTAssertEqual(core.state.favicons.image(of: opened.rawValue), pulled)
        XCTAssertEqual(core.state.favicons.image(of: copy.rawValue), pulled)
        XCTAssertEqual(store.session.space(id: spaceID)?.tabs.first { $0.id == copy }?.faviconData, pulled)

        let workspaceID = store.window.workspaceID
        let replay = CoreState()
        for batch in batches {
            apply(batch, to: replay)
            let values = Self.values(of: replay, workspaceID)
            XCTAssertFalse(notifies(replay) { apply(batch, to: replay) }, "A batch applied again notified: \(batch)")
            XCTAssertEqual(Self.values(of: replay, workspaceID), values)
        }

        let live = try XCTUnwrap(core.state.workspaces[workspaceID])
        let replayed = try XCTUnwrap(replay.workspaces[workspaceID])
        XCTAssertEqual(Self.values(of: replay, workspaceID), Self.values(of: core.state, workspaceID))
        XCTAssertEqual(replayed.spaces.models.count, original.spaces.count + 1)
        XCTAssertEqual(live.spaces.model(spaceID.rawValue)?.settings.name, "Renamed Space")
        // The replay was offered no images, so it matches the copy without them.
        let session = BrowserCoreSessionAuthority.compact(store.session)
        XCTAssertEqual(replayed.spaces.values.map { BrowserSpace(core: $0) { _ in nil } }, session.spaces)
        XCTAssertEqual(replayed.defaultSpaceID, session.defaultSpaceID?.rawValue)
        XCTAssertEqual(replayed.isDisposableSeed, session.disposableSeedMarker != nil)
        XCTAssertEqual(replayed.appPreferences.map(BrowserAppPreferences.init(core:)), session.appPreferences)
    }

    func testAChangeNotifiesOnlyTheObjectsWhoseValuesItChanges() throws {
        let core = CrestCore()
        let store = BrowserStore(session: .preview, core: core)
        let other = store.makeWindowStore()
        let space = try XCTUnwrap(core.state.workspaces[store.window.workspaceID]?.spaces.models.first)
        let tabs = space.tabs.models
        XCTAssertGreaterThan(tabs.count, 1)
        let (renamed, sibling) = (tabs[0], tabs[1])

        // An equal value notifies no one, whether it reaches the model itself
        // or arrives as a change.
        XCTAssertFalse(notifies({ _ = renamed.value }) { renamed.update(renamed.value) })
        XCTAssertFalse(
            notifies(core.state) {
                core.state.apply(
                    TabsChanged(
                        workspaceID: store.window.workspaceID, spaceID: space.id, updated: space.tabs.values,
                        removed: [], order: nil))
            })

        // A new custom title notifies the readers of that title and no one else.
        let customTitle = tripwire { _ = renamed.customTitle }
        let renamedURL = tripwire { _ = renamed.url }
        let siblingTab = tripwire { _ = sibling.value }
        let list = tripwire { _ = space.tabs.models }
        let spaces = tripwire { _ = core.state.workspaces[store.window.workspaceID]?.spaces.models }
        let records = tripwire {
            _ = space.settings.value
            _ = space.history.entries
            _ = space.archive.entries
            _ = space.folders.models
        }
        let otherWindow = tripwire { _ = core.state.windows[other.windowID.rawValue]?.value }
        XCTAssertTrue(
            store.setTabCustomTitle("Renamed", for: TabID(rawValue: renamed.id), in: SpaceID(rawValue: space.id)))
        XCTAssertEqual(renamed.customTitle, "Renamed")
        XCTAssertTrue(customTitle.isTripped)
        XCTAssertFalse(renamedURL.isTripped)
        XCTAssertFalse(siblingTab.isTripped)
        XCTAssertFalse(list.isTripped)
        XCTAssertFalse(spaces.isTripped)
        XCTAssertFalse(records.isTripped)

        // Showing a tab in one window never notifies another window's readers.
        let shown = tripwire { _ = core.state.windows[store.windowID.rawValue]?.value }
        XCTAssertTrue(store.activateSessionTab(TabID(rawValue: sibling.id), in: SpaceID(rawValue: space.id)))
        XCTAssertTrue(shown.isTripped)
        XCTAssertFalse(otherWindow.isTripped)
    }

    // MARK: - Helpers

    private func apply(_ batch: [Change], to state: CoreState) {
        for change in batch { state.apply(change) }
        state.finishBatch(batch)
    }

    /// The workspace's records and members, and every window's, as values.
    private static func values(of state: CoreState, _ workspaceID: UUID) -> [String] {
        guard let workspace = state.workspaces[workspaceID] else { return [] }
        return [
            String(describing: workspace.spaces.values), String(describing: workspace.defaultSpaceID),
            String(describing: workspace.isDisposableSeed), String(describing: workspace.spaceDeletions),
            String(describing: workspace.appPreferences),
            String(describing: state.windows.values.map(\.value).sorted { $0.id.uuidString < $1.id.uuidString }),
        ]
    }

    /// Whether `body` notifies any reader of everything `state` holds.
    private func notifies(_ state: CoreState, _ body: () -> Void) -> Bool {
        notifies(
            {
                for workspace in state.workspaces.values {
                    _ = workspace.spaces.values
                    _ = (workspace.defaultSpaceID, workspace.isDisposableSeed, workspace.spaceDeletions)
                    _ = workspace.appPreferences
                    for space in workspace.spaces.models {
                        _ = (space.splitGroups, space.history.entries, space.archive.entries)
                        for tab in space.tabs.models { _ = state.favicons.image(of: tab.id) }
                    }
                }
                _ = state.windows.values.map(\.value)
            }, body)
    }

    private func notifies(_ read: () -> Void, _ body: () -> Void) -> Bool {
        let wire = tripwire(read)
        body()
        return wire.isTripped
    }

    private func tripwire(_ read: () -> Void) -> Tripwire {
        let wire = Tripwire()
        withObservationTracking(read) { wire.trip() }
        return wire
    }
}

/// Records that an observation fired. Observation calls it synchronously on
/// the main actor, before the change it reports.
private final class Tripwire: @unchecked Sendable {
    private(set) var isTripped = false

    func trip() {
        isTripped = true
    }
}
