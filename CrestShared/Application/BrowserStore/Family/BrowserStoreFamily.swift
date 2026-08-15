import Foundation
import Observation

@Observable
@MainActor
final class BrowserStoreFamily {
    private struct WeakStore {
        weak var value: BrowserStore?
    }

    private var stores: [WeakStore] = []
    private(set) var authoritativeSession: BrowserSession
    private(set) var deletingSpaceIDs: Set<SpaceID> = []
    @ObservationIgnored private var lastCleanupSweepAt: Date?

    init(session: BrowserSession) {
        authoritativeSession = session
    }

    func register(_ store: BrowserStore) {
        stores.removeAll { $0.value == nil }
        stores.append(WeakStore(value: store))
    }

    func publish(_ session: BrowserSession, from source: BrowserStore) {
        authoritativeSession = session
        stores.removeAll { $0.value == nil }
        for store in stores.compactMap(\.value) where store !== source {
            store.receiveSharedSession(session)
        }
    }

    /// Claims the next retention sweep for the whole family. There is no primary
    /// store — every window's store publishes into the same session — so the
    /// claim is what keeps several windows from sweeping the same session over
    /// and over as each one becomes active.
    func beginCleanupSweep(at now: Date) -> Bool {
        guard
            BrowserCurrentTabCleanupSchedule.allowsSweep(
                lastSweptAt: lastCleanupSweepAt,
                now: now
            )
        else { return false }
        lastCleanupSweepAt = now
        return true
    }

    func beginDeletingSpace(_ id: SpaceID) -> Bool {
        deletingSpaceIDs.insert(id).inserted
    }

    func finishDeletingSpace(_ id: SpaceID) {
        deletingSpaceIDs.remove(id)
    }

    func resetDeletionState() {
        deletingSpaceIDs.removeAll()
    }
}
