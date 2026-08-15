import Foundation
import XCTest

@testable import Crest

/// Split View column widths live in window state: per window, per device, never
/// synced. These cases pin the three things that make that safe: validation on
/// capture, pruning on repair, and decoding a record written before the field
/// existed — which is every record installed copies of Crest have on disk.
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

    func testCaptureReplacesTheFractionsAGroupAlreadyHad() {
        let group = SplitGroupID()
        var state = makeState()

        state.captureSplitLayout(fractions: [0.5, 0.5], for: group)
        state.captureSplitLayout(fractions: [0.7, 0.3], for: group)

        XCTAssertEqual(state.splitColumnFractions(for: group), [0.7, 0.3])
    }

    func testCaptureNormalizesFractionsThatDriftFromTheWholeContainer() {
        let group = SplitGroupID()
        var state = makeState()

        state.captureSplitLayout(fractions: [0.5, 0.25], for: group)

        let stored = state.splitColumnFractions(for: group) ?? []
        XCTAssertEqual(stored.reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertEqual(stored.first ?? 0, 2.0 / 3, accuracy: 0.0001)
    }

    func testCaptureLeavesFractionsThatAlreadySumToOneUntouched() {
        let group = SplitGroupID()
        var state = makeState()
        let fractions = BrowserSplitColumnLayout.equalFractions(count: 3)

        state.captureSplitLayout(fractions: fractions, for: group)

        XCTAssertEqual(
            state.splitColumnFractions(for: group),
            fractions,
            "Rounding a list that is already normalized would churn the record."
        )
    }

    func testCaptureIgnoresFractionsThatCannotDescribeColumns() {
        let group = SplitGroupID()
        var state = makeState()

        let rejected: [[Double]] = [
            [],
            [0.2, 0.2, 0.2, 0.2, 0.2],
            [Double.nan, 0.5],
            [.infinity, 0.5],
            [0, 1],
            [-0.5, 1.5],
            [1.5, 0.5],
        ]
        for fractions in rejected {
            state.captureSplitLayout(fractions: fractions, for: group)

            XCTAssertNil(
                state.splitColumnFractionsByGroup,
                "\(fractions) is not a column layout and must not be stored."
            )
        }
    }

    func testRepairForgetsFractionsForAGroupNothingRendersAnymore() throws {
        let group = SplitGroupID()
        let session = makeSession(memberCount: 2, group: group)
        var state = BrowserWindowState(restoring: session)
        state.captureSplitLayout(fractions: [0.6, 0.4], for: group)
        state.captureSplitLayout(fractions: [0.5, 0.5], for: SplitGroupID())

        state.repair(using: session)

        XCTAssertEqual(state.splitColumnFractions(for: group), [0.6, 0.4])
        XCTAssertEqual(
            try XCTUnwrap(state.splitColumnFractionsByGroup).count,
            1,
            "A group no Space renders is a group whose widths mean nothing."
        )
    }

    func testRepairForgetsFractionsWhoseColumnCountNoLongerMatches() {
        let group = SplitGroupID()
        var state = BrowserWindowState(restoring: makeSession(memberCount: 3, group: group))
        state.captureSplitLayout(fractions: [0.5, 0.3, 0.2], for: group)

        state.repair(using: makeSession(memberCount: 2, group: group))

        XCTAssertNil(
            state.splitColumnFractionsByGroup,
            "A group that gained or lost a member starts over at equal columns."
        )
    }

    func testRepairReturnsTheWholeRecordToNilOnceItEmpties() {
        let group = SplitGroupID()
        var state = makeState()
        state.captureSplitLayout(fractions: [0.6, 0.4], for: group)

        state.repair(using: makeSession(memberCount: 0, group: group))

        XCTAssertNil(state.splitColumnFractionsByGroup)
    }

    func testRepairLeavesAWindowThatNeverResizedAnythingAlone() {
        let group = SplitGroupID()
        var state = BrowserWindowState(restoring: makeSession(memberCount: 2, group: group))

        state.repair(using: makeSession(memberCount: 2, group: group))

        XCTAssertNil(state.splitColumnFractionsByGroup)
    }

    func testASubRenderableRunKeepsNoFractions() {
        let group = SplitGroupID()
        var state = makeState()
        state.captureSplitLayout(fractions: [1], for: group)

        state.repair(using: makeSession(memberCount: 1, group: group))

        XCTAssertNil(
            state.splitColumnFractionsByGroup,
            "A lone member presents as a plain tab, so it owns no columns."
        )
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
