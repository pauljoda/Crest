import Foundation
import Observation

@Observable
@MainActor
final class BrowserStoreFamily {
    private struct WeakStore {
        weak var value: BrowserStore?
    }

    private var stores: [WeakStore] = []
    /// The single owner of browsing data. Window stores project their local
    /// selection over this value; none retains a second authoritative session.
    private(set) var authoritativeSession: BrowserSession
    let temporarySourceAssignment: BrowserSpaceRuntimeAssignment?
    let temporarySettingsBrowser: BrowserStore?
    private(set) var syncRevision: BrowserStoreSyncRevision = .initial
    private(set) var deletingSpaceIDs: Set<SpaceID> = []
    @ObservationIgnored private var lastCleanupSweepAt: Date?

    init(
        session: BrowserSession, temporarySourceAssignment: BrowserSpaceRuntimeAssignment? = nil,
        temporarySettingsBrowser: BrowserStore? = nil
    ) {
        authoritativeSession = session
        self.temporarySourceAssignment = temporarySourceAssignment
        self.temporarySettingsBrowser = temporarySettingsBrowser
    }

    /// Temporary tabs retain their own organization, but profile identity and
    /// privacy always read through to their source, including during deletion.
    var currentSession: BrowserSession {
        guard let assignment = temporarySourceAssignment, let source = temporarySettingsBrowser else {
            return authoritativeSession
        }
        var current = authoritativeSession
        guard let borrowed = source.space(matching: assignment),
            let local = current.space(id: assignment.spaceID)
        else {
            current.spaces = []
            return current
        }
        current.spaces = [BrowserTemporaryWorkspacePolicy.borrowing(borrowed, keeping: local)]
        return current
    }

    func register(_ store: BrowserStore) {
        stores.removeAll { $0.value == nil }
        stores.append(WeakStore(value: store))
    }

    func replaceSession(_ session: BrowserSession, from source: BrowserStore, adoptingSelection: Bool = true) {
        let previous = authoritativeSession
        authoritativeSession = session
        reconcileStores(after: previous, from: adoptingSelection ? source : nil)
    }

    /// Installs both prepared graphs before any window reconciles its selection.
    /// This is synchronous on the main actor, so a transfer has no partial
    /// source/destination state across an actor suspension.
    static func replaceSessions(
        source: BrowserStore, sourceSession: BrowserSession,
        destination: BrowserStore, destinationSession: BrowserSession
    ) {
        precondition(source.family !== destination.family)
        let previousSource = source.family.authoritativeSession
        let previousDestination = destination.family.authoritativeSession
        source.family.authoritativeSession = sourceSession
        destination.family.authoritativeSession = destinationSession
        source.family.reconcileStores(after: previousSource, from: source)
        destination.family.reconcileStores(after: previousDestination, from: destination)
    }

    private func reconcileStores(after previous: BrowserSession, from source: BrowserStore?) {
        stores.removeAll { $0.value == nil }
        for store in stores.compactMap(\.value) {
            store.receiveFamilySessionChange(
                from: previous, to: authoritativeSession, adoptingSelection: store === source
            )
        }
    }

    @discardableResult
    func publish(
        _ session: BrowserSession,
        from source: BrowserStore,
        at reservedRevision: BrowserStoreSyncRevision? = nil
    ) -> BrowserStoreSyncRevision {
        let revision = reservedRevision ?? reserveSyncRevision()
        precondition(revision == syncRevision)
        // Mutations already updated the one shared graph. Persistence advances
        // its sync revision without copying it back into every window.
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
