import Foundation
import XCTest

@testable import Crest

/// The persisted window-state set has to limit itself.
///
/// Nothing in the app removes a record: `BrowserWindowStateStore.init` saves
/// unconditionally, and every unrestored iOS scene comes back under a fresh random
/// `BrowserWindowID`. Without a cap each force-quit leaves one more orphan in
/// `UserDefaults` forever.
@MainActor
final class BrowserSessionWindowStateLimitTests: XCTestCase {
    func testTheStoredSetStopsGrowingOnceItIsFull() async throws {
        let harness = makeHarness(cap: 4)
        let session = BrowserSession.preview

        let ids = (0..<20).map { _ in BrowserWindowID() }
        for id in ids {
            harness.persistence.save(BrowserWindowState(id: id, restoring: session))
        }
        await harness.persistence.flushPendingSaves()

        XCTAssertEqual(try storedStates(in: harness).count, 4)
        XCTAssertEqual(
            try storedStates(in: harness).map(\.id),
            Array(ids.suffix(4)),
            "The cap keeps the windows saved most recently."
        )
        for id in ids.dropLast(4) {
            XCTAssertNil(harness.persistence.load(id: id))
        }
        for id in ids.suffix(4) {
            XCTAssertNotNil(harness.persistence.load(id: id))
        }
    }

    func testANewSceneEveryLaunchCannotAccumulateRecords() async throws {
        let harness = makeHarness()
        let session = BrowserSession.preview

        // One record per simulated force-quit, far past the cap.
        for _ in 0..<200 {
            harness.persistence.save(
                BrowserWindowState(id: BrowserWindowID(), restoring: session)
            )
        }
        await harness.persistence.flushPendingSaves()

        XCTAssertEqual(
            try storedStates(in: harness).count,
            UserDefaultsBrowserWindowStatePersistence.maximumStoredStateCount
        )
    }

    func testAWindowStillInUseIsNotEvictedByOlderNeighbours() async throws {
        let harness = makeHarness(cap: 3)
        let session = BrowserSession.preview
        let live = BrowserWindowID()
        harness.persistence.save(BrowserWindowState(id: live, restoring: session))

        for _ in 0..<2 {
            harness.persistence.save(
                BrowserWindowState(id: BrowserWindowID(), restoring: session)
            )
            // The live window keeps working, so it keeps saving.
            harness.persistence.save(BrowserWindowState(id: live, restoring: session))
        }
        await harness.persistence.flushPendingSaves()

        XCTAssertNotNil(harness.persistence.load(id: live))
        XCTAssertEqual(try storedStates(in: harness).last?.id, live)
    }

    func testTheFixedMacWindowKeepsExactlyOneRecordAcrossEveryLaunch() async throws {
        let harness = makeHarness()
        let session = BrowserSession.preview

        for _ in 0..<50 {
            let store = BrowserWindowStateStore(
                id: .main,
                session: session,
                persistence: harness.persistence
            )
            store.selectSpace(session.spaces[1].id, session: session)
        }
        await harness.persistence.flushPendingSaves()

        let stored = try storedStates(in: harness)
        XCTAssertEqual(stored.count, 1, "macOS restores one shell under one identity.")
        XCTAssertEqual(stored.first?.id, .main)
        XCTAssertEqual(
            harness.persistence.load(id: .main)?.selectedSpaceID,
            session.spaces[1].id,
            "Capping must not cost the one Mac window its selection."
        )
    }

    func testAStoredRecordSurvivesAReloadThroughTheStore() async throws {
        let harness = makeHarness()
        let session = BrowserSession.preview
        let id = BrowserWindowID()
        let first = BrowserWindowStateStore(
            id: id,
            session: session,
            persistence: harness.persistence
        )
        first.selectSpace(session.spaces[1].id, session: session)
        await harness.persistence.flushPendingSaves()

        let reopened = BrowserWindowStateStore(
            id: id,
            session: session,
            persistence: makeHarness(defaults: harness.defaults).persistence
        )

        XCTAssertEqual(reopened.selectedSpaceID, session.spaces[1].id)
    }

    // MARK: - Helpers

    private struct Harness {
        let defaults: UserDefaults
        let key: String
        let persistence: UserDefaultsBrowserWindowStatePersistence
    }

    private func makeHarness(
        defaults: UserDefaults? = nil,
        cap: Int = UserDefaultsBrowserWindowStatePersistence.maximumStoredStateCount
    ) -> Harness {
        let resolvedDefaults: UserDefaults
        if let defaults {
            resolvedDefaults = defaults
        } else {
            let suiteName = "BrowserSessionWindowStateLimitTests.\(UUID().uuidString)"
            resolvedDefaults = UserDefaults(suiteName: suiteName) ?? .standard
            addTeardownBlock {
                resolvedDefaults.removePersistentDomain(forName: suiteName)
            }
        }
        let key = "crest.windows.v1"
        return Harness(
            defaults: resolvedDefaults,
            key: key,
            persistence: UserDefaultsBrowserWindowStatePersistence(
                defaults: resolvedDefaults,
                key: key,
                maximumStoredStateCount: cap
            )
        )
    }

    private func storedStates(in harness: Harness) throws -> [BrowserWindowState] {
        let data = try XCTUnwrap(harness.defaults.data(forKey: harness.key))
        return try JSONDecoder().decode([BrowserWindowState].self, from: data)
    }
}
