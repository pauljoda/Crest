import Foundation
import Observation

@Observable
@MainActor
final class BrowserStoreFamily {
    private struct WeakStore {
        weak var value: BrowserStore?
    }

    private var stores: [WeakStore] = []
    #if CREST_CORE_BACKED
    private let core: BrowserCoreSessionAuthority
    var authoritativeSession: BrowserSession { core.projection }
    #else
    private(set) var authoritativeSession: BrowserSession
    #endif
    let temporarySourceAssignment: BrowserSpaceRuntimeAssignment?
    let temporarySettingsBrowser: BrowserStore?
    private(set) var syncRevision: BrowserStoreSyncRevision = .initial
    private(set) var deletingSpaceIDs: Set<SpaceID> = []
    @ObservationIgnored private var lastCleanupSweepAt: Date?

    init(
        session: BrowserSession, browsingMode: BrowserBrowsingMode = .standard,
        temporarySourceAssignment: BrowserSpaceRuntimeAssignment? = nil,
        temporarySettingsBrowser: BrowserStore? = nil
    ) {
        #if CREST_CORE_BACKED
        core = BrowserCoreSessionAuthority(session: session,
            workspaceKind: temporarySourceAssignment != nil ? "temporary" : browsingMode.isPrivate ? "private" : "persistent")
        #else
        authoritativeSession = session
        #endif
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
        #if CREST_CORE_BACKED
        if let sync = store.syncCoordinator {
            do { try core.attachSync(sync.core) }
            catch { preconditionFailure("Cannot attach sync to the core session: \(error)") }
        }
        #endif
        stores.removeAll { $0.value == nil }
        stores.append(WeakStore(value: store))
    }

    func replaceSession(_ session: BrowserSession, from source: BrowserStore, adoptingSelection: Bool = true) {
        let previous = authoritativeSession
        #if CREST_CORE_BACKED
        do { try core.replace(with: session) }
        catch { source.localSyncErrorDescription = "Core session update failed: \(error)"; return }
        #else
        authoritativeSession = session
        #endif
        reconcileStores(after: previous, from: adoptingSelection ? source : nil)
    }

    #if CREST_CORE_BACKED
    func installSyncedSession(_ session: BrowserSession, journal: BrowserSyncJournal,
        journalPersistence: any BrowserSyncJournalPersisting, transaction: BrowserCoreSyncTransaction, from source: BrowserStore) throws {
        let previous = authoritativeSession
        try core.replaceDurably(with: session, sync: transaction) { checkpoint in
            if let storage = source.persistence as? BrowserTransactionalSessionPersistence {
                guard storage.owns(journalPersistence) else {
                    throw BrowserTransactionalSessionPersistence.StorageError.invalidCheckpoint
                }
                try storage.commit(session, checkpoint: checkpoint, journal: journal)
            } else {
                // Ephemeral workspaces and injected test adapters have no
                // cross-launch recovery. Live persistent compositions use the
                // transactional adapter above.
                try journalPersistence.save(journal)
                source.persistence.save(session, scope: .everything, checkpoint: checkpoint)
            }
        }
        reconcileStores(after: previous, from: source)
    }

    func executeSpace(_ operation: String, in spaceID: SpaceID? = nil, arguments: [String: Any],
        from source: BrowserStore, at date: Date = .now) -> Bool {
        let previous = authoritativeSession
        do {
            let changed = try core.executeSpace(operation, in: spaceID, arguments: arguments, window: source.session, at: date)
            reconcileStores(after: previous, from: source)
            return changed
        } catch {
            source.localSyncErrorDescription = "Core Space command failed: \(error)"
            return false
        }
    }

    func execute(_ operation: String, in spaceID: SpaceID, arguments: [String: Any],
        from source: BrowserStore, at date: Date) -> BrowserCoreSessionEditing.Result? {
        let previous = authoritativeSession
        do {
            let result = try core.execute(operation, in: spaceID, arguments: arguments, window: source.session, at: date)
            reconcileStores(after: previous, from: source)
            return result
        } catch {
            source.localSyncErrorDescription = "Core command failed: \(error)"
            return nil
        }
    }
    #endif

    /// Installs both prepared graphs before any window reconciles its selection.
    /// This is synchronous on the main actor, so a transfer has no partial
    /// source/destination state across an actor suspension.
    @discardableResult
    static func replaceSessions(
        source: BrowserStore, sourceSession: BrowserSession,
        destination: BrowserStore, destinationSession: BrowserSession
    ) -> Bool {
        precondition(source.family !== destination.family)
        let previousSource = source.family.authoritativeSession
        let previousDestination = destination.family.authoritativeSession
        #if CREST_CORE_BACKED
        do {
            try BrowserCoreSessionAuthority.replacePair(
                source: source.family.core, sourceSession: sourceSession,
                destination: destination.family.core, destinationSession: destinationSession)
        } catch {
            source.localSyncErrorDescription = "Core workspace transfer failed: \(error)"
            destination.localSyncErrorDescription = source.localSyncErrorDescription
            return false
        }
        #else
        source.family.authoritativeSession = sourceSession
        destination.family.authoritativeSession = destinationSession
        #endif
        source.family.reconcileStores(after: previousSource, from: source)
        destination.family.reconcileStores(after: previousDestination, from: destination)
        return true
    }

    func save(_ session: BrowserSession, to persistence: any BrowserSessionPersisting,
        scope: BrowserSessionSaveScope = .everything) throws {
        #if CREST_CORE_BACKED
        let snapshot = try core.checkpoint(for: session)
        persistence.save(session, scope: scope, checkpoint: snapshot)
        #else
        persistence.save(session, scope: scope)
        #endif
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
