import Foundation
import XCTest

@testable import Crest

/// Split View column widths live in window state: per window, per device, never
/// synced. The core's window-state rules own validation on capture and pruning
/// on repair (`WindowStatePolicyTests`); these cases pin the native record:
/// storing through the adapter, decoding a record written before the field
/// existed — which is every record installed copies of Crest have on disk — and
/// the store's durable writes.
final class BrowserWindowStateSplitLayoutTests: XCTestCase {
    func testCapturedFractionsComeBackForTheirOwnGroup() {
        let first = SplitGroupID()
        let second = SplitGroupID()
        var state = makeState()

        state.captureSplitLayout(fractions: [0.6, 0.4], for: first)
        state.captureSplitLayout(fractions: [0.25, 0.5, 0.25], for: second)

        XCTAssertEqual(state.splitColumnFractions(for: first), [0.6, 0.4])
        XCTAssertEqual(state.splitColumnFractions(for: second), [0.25, 0.5, 0.25])
        XCTAssertNil(state.splitColumnFractions(for: SplitGroupID()))
    }

    // MARK: - Coding

    func testAStateWrittenBeforeSplitViewStillDecodes() throws {
        let space = makeSpace(memberCount: 2, group: SplitGroupID())
        let legacy = LegacyWindowState(
            id: BrowserWindowID(),
            selectedSpaceID: space.id,
            selectedTabIDsBySpace: [space.id: try XCTUnwrap(space.tabs.first).id],
            sidebarWidth: 301,
            sidebarIsPresented: true
        )
        let data = try JSONEncoder().encode(legacy)

        XCTAssertFalse(
            try XCTUnwrap(String(data: data, encoding: .utf8))
                .contains("splitColumnFractionsByGroup")
        )

        let decoded = try JSONDecoder().decode(BrowserWindowState.self, from: data)

        XCTAssertEqual(decoded.id, legacy.id)
        XCTAssertEqual(decoded.selectedSpaceID, space.id)
        XCTAssertEqual(decoded.sidebarWidth, 301)
        XCTAssertEqual(decoded.sidebarIsPresented, true)
        XCTAssertNil(decoded.splitColumnFractionsByGroup)
    }

    func testCapturedFractionsSurviveAJSONRoundTrip() throws {
        let group = SplitGroupID()
        var state = makeState()
        state.captureSplitLayout(fractions: [0.6, 0.4], for: group)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BrowserWindowState.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.splitColumnFractions(for: group), [0.6, 0.4])
    }

    // MARK: - Store

    @MainActor
    func testTheStoreSavesACaptureOnceAndSkipsOneThatChangesNothing() {
        let group = SplitGroupID()
        let session = makeSession(memberCount: 2, group: group)
        let persistence = CountingPersistence()
        let store = BrowserWindowStateStore(
            id: BrowserWindowID(),
            session: session,
            persistence: persistence
        )
        let savesAfterLaunch = persistence.saveCount

        store.captureSplitLayout(fractions: [0.6, 0.4], for: group)

        XCTAssertEqual(store.splitColumnFractions(for: group), [0.6, 0.4])
        XCTAssertEqual(persistence.saveCount, savesAfterLaunch + 1)

        store.captureSplitLayout(fractions: [0.6, 0.4], for: group)
        store.captureSplitLayout(fractions: [], for: group)

        XCTAssertEqual(
            persistence.saveCount,
            savesAfterLaunch + 1,
            "Only a real change earns a durable write."
        )
    }

    @MainActor
    func testTheStorePrunesFractionsWhenItReconcilesWithTheSession() {
        let group = SplitGroupID()
        let persistence = CountingPersistence()
        let store = BrowserWindowStateStore(
            id: BrowserWindowID(),
            session: makeSession(memberCount: 2, group: group),
            persistence: persistence
        )
        store.captureSplitLayout(fractions: [0.6, 0.4], for: group)

        store.reconcile(with: makeSession(memberCount: 0, group: group))

        XCTAssertNil(store.splitColumnFractions(for: group))
    }

    // MARK: - Helpers

    private final class CountingPersistence: BrowserWindowStatePersisting, @unchecked Sendable {
        private(set) var saveCount = 0
        private var states: [BrowserWindowID: BrowserWindowState] = [:]

        func load(id: BrowserWindowID) -> BrowserWindowState? {
            states[id]
        }

        func save(_ state: BrowserWindowState) {
            saveCount += 1
            states[state.id] = state
        }

        func remove(id: BrowserWindowID) {
            states[id] = nil
        }
    }

    private struct LegacyWindowState: Encodable {
        let id: BrowserWindowID
        let selectedSpaceID: SpaceID
        let selectedTabIDsBySpace: [SpaceID: TabID]
        let sidebarWidth: Double?
        let sidebarIsPresented: Bool?
    }

    private func makeState() -> BrowserWindowState {
        BrowserWindowState(
            id: BrowserWindowID(),
            selectedSpaceID: SpaceID(),
            selectedTabIDsBySpace: [:]
        )
    }

    private func makeSession(memberCount: Int, group: SplitGroupID) -> BrowserSession {
        let space = makeSpace(memberCount: memberCount, group: group)
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }

    private func makeSpace(memberCount: Int, group: SplitGroupID) -> BrowserSpace {
        let members = (0..<memberCount).map { index in
            makeTab("Member \(index)", group: group)
        }
        let tabs = members + [makeTab("Outsider")]
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs.first?.id
        )
    }

    private func makeTab(_ title: String, group: SplitGroupID? = nil) -> BrowserTab {
        BrowserTab(
            title: title,
            url: URL(string: "https://example.com/\(title.replacingOccurrences(of: " ", with: "-"))"),
            placement: .current,
            splitGroupID: group,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
