import Foundation
import Observation

@Observable
@MainActor
final class BrowserStoreFamily {
    private struct WeakStore {
        weak var value: BrowserStore?
    }

    private var stores: [WeakStore] = []
    let extensionTabGroups = BrowserExtensionTabGroupStore()
    private(set) var authoritativeSession: BrowserSession
    private(set) var syncRevision: BrowserStoreSyncRevision = .initial
    private(set) var deletingSpaceIDs: Set<SpaceID> = []
    @ObservationIgnored private var lastCleanupSweepAt: Date?

    init(session: BrowserSession) {
        authoritativeSession = session
        extensionTabGroups.sessionSnapshot = { [weak self] in self?.authoritativeSession }
        extensionTabGroups.commitSession = { [weak self] next in
            guard let store = self?.stores.compactMap(\.value).first else { return }
            store.receiveSharedSession(next)
            store.persist(syncUrgency: .coalesced, scope: .core)
        }
        extensionTabGroups.repair(using: session)
    }

    func register(_ store: BrowserStore) {
        stores.removeAll { $0.value == nil }
        stores.append(WeakStore(value: store))
    }

    @discardableResult
    func publish(
        _ session: BrowserSession,
        from source: BrowserStore,
        at reservedRevision: BrowserStoreSyncRevision? = nil
    ) -> BrowserStoreSyncRevision {
        let revision = reservedRevision ?? reserveSyncRevision()
        precondition(revision == syncRevision)
        authoritativeSession = session
        extensionTabGroups.repair(using: session)
        stores.removeAll { $0.value == nil }
        for store in stores.compactMap(\.value) where store !== source {
            store.receiveSharedSession(session)
        }
        return revision
    }

    /// Orders every window's background sync work against the one shared
    /// session. A window may still hold a task captured before another window's
    /// edit; invalidating its local generation avoids needless work, while the
    /// revision lets the shared coordinator reject it even if it was already
    /// running when the newer edit arrived.
    @discardableResult
    func reserveSyncRevision() -> BrowserStoreSyncRevision {
        syncRevision = syncRevision.successor()
        stores.removeAll { $0.value == nil }
        for store in stores.compactMap(\.value) {
            store.invalidatePendingSyncStage()
        }
        return syncRevision
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
