import Foundation
import Observation

@Observable
@MainActor
final class BrowserStoreFamily {
    private struct WeakStore {
        weak var value: BrowserStore?
    }

    private var stores: [WeakStore] = []
    private let core: BrowserCoreSessionAuthority
    private struct WeakFamily { weak var value: BrowserStoreFamily? }
    private var borrowedFamilies: [WeakFamily] = []
    private var borrowedSourceIsAvailable = true
    var authoritativeSession: BrowserSession { core.projection }
    let temporarySourceAssignment: BrowserSpaceRuntimeAssignment?
    let temporarySettingsBrowser: BrowserStore?
    private(set) var syncRevision: BrowserStoreSyncRevision = .initial
    private var activeSpaceDeletions: Set<SpaceID> = []
    var deletingSpaceIDs: Set<SpaceID> {
        activeSpaceDeletions.union(authoritativeSession.spaceDeletions?.map(\.spaceID) ?? [])
    }
    @ObservationIgnored private weak var spaceDataDeleter: (any BrowserSpaceDataDeleting)?
    @ObservationIgnored private weak var spaceCleanupStore: BrowserStore?
    @ObservationIgnored private(set) var spaceCleanupTask: Task<Void, Never>?
    @ObservationIgnored private var lastCleanupSweepAt: Date?
    @ObservationIgnored weak var pageDismissalAuthorizer: (any BrowserPageDismissalAuthorizing)?

    init(
        session: BrowserSession, browsingMode: BrowserBrowsingMode = .standard,
        temporarySourceAssignment: BrowserSpaceRuntimeAssignment? = nil,
        temporarySettingsBrowser: BrowserStore? = nil
    ) {
        precondition(temporarySourceAssignment == nil, "Borrowed workspaces must be created by their core owner")
        core = BrowserCoreSessionAuthority(session: session,
            workspaceKind: browsingMode.isPrivate ? "private" : "persistent",
            privateBrowsing: browsingMode.isPrivate)
        self.temporarySourceAssignment = temporarySourceAssignment
        self.temporarySettingsBrowser = temporarySettingsBrowser
    }

    private init(core: BrowserCoreSessionAuthority, assignment: BrowserSpaceRuntimeAssignment, settingsBrowser: BrowserStore) {
        self.core = core; temporarySourceAssignment = assignment; temporarySettingsBrowser = settingsBrowser
    }

    func makeBorrowed(in assignment: BrowserSpaceRuntimeAssignment, settingsBrowser: BrowserStore) throws -> BrowserStoreFamily {
        let child = BrowserStoreFamily(core: try core.makeBorrowed(in: assignment),
            assignment: assignment, settingsBrowser: settingsBrowser)
        borrowedFamilies.removeAll { $0.value == nil }
        borrowedFamilies.append(WeakFamily(value: child))
        return child
    }

    func refreshBorrowed() -> Bool {
        guard temporarySourceAssignment != nil else { return false }
        let previous = authoritativeSession
        do {
            let changed = try core.refreshBorrowed()
            borrowedSourceIsAvailable = true
            if changed { reconcileStores(after: previous, from: nil) }
            return true
        } catch {
            borrowedSourceIsAvailable = false
            return false
        }
    }

    /// Composition supplies the engine adapter once. Sync schedules it only
    /// after the core intent and accepted journal have committed together.
    func configureSpaceDataCleanup(_ dataDeleter: any BrowserSpaceDataDeleting, from store: BrowserStore) {
        spaceDataDeleter = dataDeleter
        spaceCleanupStore = store
        scheduleSpaceDataCleanup()
    }

    private func scheduleSpaceDataCleanup() {
        guard spaceCleanupTask == nil, !(authoritativeSession.spaceDeletions ?? []).isEmpty,
            let dataDeleter = spaceDataDeleter, let store = spaceCleanupStore else { return }
        spaceCleanupTask = Task { [weak self] in
            await store.resumePendingSpaceDeletions(dataDeleter: dataDeleter)
            self?.spaceCleanupTask = nil
        }
    }

    /// Temporary tabs retain their own organization, but profile identity and
    /// privacy always read through to their source, including during deletion.
    var currentSession: BrowserSession {
        guard let assignment = temporarySourceAssignment, let source = temporarySettingsBrowser else {
            return authoritativeSession
        }
        var current = authoritativeSession
        guard borrowedSourceIsAvailable, source.space(matching: assignment) != nil else {
            current.spaces = []
            return current
        }
        return current
    }

    func register(_ store: BrowserStore) {
        if let sync = store.syncCoordinator {
            do { try core.attachSync(sync.core) }
            catch { preconditionFailure("Cannot attach sync to the core session: \(error)") }
        }
        stores.removeAll { $0.value == nil }
        stores.append(WeakStore(value: store))
    }

    func replaceSession(_ session: BrowserSession, from source: BrowserStore, adoptingSelection: Bool = true) {
        let previous = authoritativeSession
        do { try core.replace(with: session) }
        catch { source.localSyncErrorDescription = "Core session update failed: \(error)"; return }
        reconcileStores(after: previous, from: adoptingSelection ? source : nil)
    }

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
        scheduleSpaceDataCleanup()
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

    func executeSpaceDurably(_ operation: String, in spaceID: SpaceID, arguments: [String: Any],
        deletionReason: BrowserSyncTombstoneReason = .superseded, from source: BrowserStore, at date: Date = .now) throws {
        let previous = authoritativeSession
        let command = try core.prepareSpace(operation, in: spaceID, arguments: arguments, window: source.session, at: date)
        try commitPreparedChange(command, previous: previous, deletionReason: deletionReason, from: source, at: date)
    }

    func importWorkspace(_ request: BrowserCoreWorkspaceImport.Request, from source: BrowserStore) throws {
        let previous = authoritativeSession
        let command = try core.prepareWorkspace(request, window: source.session)
        try commitPreparedChange(command, previous: previous, deletionReason: .superseded, from: source, at: .now)
    }

    func prepareTabBatch(_ request: BrowserTabBatchRequest, arguments: [String: Any], from store: BrowserStore,
        at date: Date) throws -> (command: BrowserCoreSessionAuthority.PreparedChange, result: BrowserTabBatchResult) {
        try core.prepareTabBatch(request, arguments: arguments, window: store.session, at: date)
    }

    func commitTabBatch(_ command: BrowserCoreSessionAuthority.PreparedChange,
        deletionReason: BrowserSyncTombstoneReason, from store: BrowserStore, at date: Date) throws {
        try commitPreparedChange(command, previous: authoritativeSession, deletionReason: deletionReason, from: store, at: date)
    }

    private func commitPreparedChange(_ command: BrowserCoreSessionAuthority.PreparedChange,
        previous: BrowserSession, deletionReason: BrowserSyncTombstoneReason, from source: BrowserStore, at date: Date) throws {
        let revision = reserveSyncRevision()
        if let sync = source.syncCoordinator {
            sync.advanceStoreRevision(to: revision)
            try sync.installLocalCommand(command.session, deletionReason: deletionReason, at: date, revision: revision) {
                session, journal, journalPersistence, transaction in
                try self.core.commitDurably(command, sync: transaction) { checkpoint in
                    if let storage = source.persistence as? BrowserTransactionalSessionPersistence {
                        guard storage.owns(journalPersistence) else { throw BrowserTransactionalSessionPersistence.StorageError.invalidCheckpoint }
                        try storage.commit(session, checkpoint: checkpoint, journal: journal)
                    } else {
                        try journalPersistence.save(journal)
                        source.persistence.save(session, scope: .everything, checkpoint: checkpoint)
                    }
                }
            }
        } else {
            try core.commitDurably(command) { checkpoint in
                if let storage = source.persistence as? BrowserTransactionalSessionPersistence {
                    try storage.commit(command.session, checkpoint: checkpoint)
                } else {
                    source.persistence.save(command.session, scope: .everything, checkpoint: checkpoint)
                }
            }
        }
        reconcileStores(after: previous, from: source)
        source.cloudSyncChangeHandler?()
    }

    /// App-wide behavior preferences. Only the preference record changes, so
    /// every window keeps its own selection.
    func executePreferences(_ request: BrowserAppPreferenceRequest, from source: BrowserStore) -> Bool {
        let previous = authoritativeSession
        do {
            let changed = try core.executePreferences(request)
            if changed { reconcileStores(after: previous, from: nil) }
            return changed
        } catch {
            source.localSyncErrorDescription = "Core preference command failed: \(error)"
            return false
        }
    }

    /// A core answer read from the owned session without changing it.
    func readCore(_ request: [String: Any]) -> Data? { try? core.read(request) }

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

    func executeRecords(_ operation: String, in spaceID: SpaceID? = nil, arguments: [String: Any] = [:],
        from source: BrowserStore, at date: Date = .now) -> Bool {
        let previous = authoritativeSession
        do {
            let changed = try core.executeRecords(operation, in: spaceID, arguments: arguments, window: source.session, at: date)
            if changed { reconcileStores(after: previous, from: source) }
            return changed
        } catch {
            source.localSyncErrorDescription = "Core record command failed: \(error)"
            return false
        }
    }

    func moveTab(_ tabID: TabID, source: BrowserSpaceRuntimeAssignment, destination: BrowserSpaceRuntimeAssignment,
        arguments: [String: Any], from store: BrowserStore, at date: Date) throws {
        let previous = authoritativeSession
        let command = try core.prepareTabMove(tabID, source: source, destination: destination,
            arguments: arguments, window: store.session, at: date)
        try commitPreparedChange(command, previous: previous, deletionReason: .superseded, from: store, at: date)
    }

    static func prepareTransfer(_ id: TabID, assignment: BrowserSpaceRuntimeAssignment,
        source: BrowserStore, destination: BrowserStore, fallback: TabID?, selecting: Bool) throws -> BrowserCoreSessionAuthority.PreparedTransfer {
        try BrowserCoreSessionAuthority.prepareTransfer(source: source.family.core, sourceWindow: source.session,
            destination: destination.family.core, destinationWindow: destination.session,
            tabID: id, assignment: assignment, fallback: fallback, selecting: selecting)
    }

    static func transfer(_ prepared: BrowserCoreSessionAuthority.PreparedTransfer,
        source: BrowserStore, destination: BrowserStore) throws {
        let previousSource = source.family.authoritativeSession
        let previousDestination = destination.family.authoritativeSession
        let sourceIsDurable = !source.isTemporaryWorkspace
        let durable = sourceIsDurable ? source : destination
        let next = sourceIsDurable ? prepared.source : prepared.destination
        let revision = durable.family.reserveSyncRevision()
        func commit(journal: BrowserSyncJournal? = nil, journalPersistence: (any BrowserSyncJournalPersisting)? = nil,
            transaction: BrowserCoreSyncTransaction? = nil) throws {
            try BrowserCoreSessionAuthority.commitTransfer(prepared, source: source.family.core,
                destination: destination.family.core, sync: transaction) { a, b in
                let checkpoint = sourceIsDurable ? a : b
                if let storage = durable.persistence as? BrowserTransactionalSessionPersistence {
                    if let journalPersistence, !storage.owns(journalPersistence) {
                        throw BrowserTransactionalSessionPersistence.StorageError.invalidCheckpoint
                    }
                    try storage.commit(next, checkpoint: checkpoint, journal: journal)
                } else {
                    if let journal, let journalPersistence { try journalPersistence.save(journal) }
                    durable.persistence.save(next, scope: .everything, checkpoint: checkpoint)
                }
                let temporary = sourceIsDurable ? destination : source
                temporary.persistence.save(sourceIsDurable ? prepared.destination : prepared.source,
                    scope: .everything, checkpoint: sourceIsDurable ? b : a)
            }
        }
        if let sync = durable.syncCoordinator {
            sync.advanceStoreRevision(to: revision)
            try sync.installLocalCommand(next, deletionReason: .superseded, at: .now, revision: revision) {
                _, journal, persistence, transaction in
                try commit(journal: journal, journalPersistence: persistence, transaction: transaction)
            }
        } else { try commit() }
        source.family.reconcileStores(after: previousSource, from: source)
        destination.family.reconcileStores(after: previousDestination, from: destination)
        durable.cloudSyncChangeHandler?()
    }

    func save(_ session: BrowserSession, to persistence: any BrowserSessionPersisting,
        scope: BrowserSessionSaveScope = .everything) throws {
        let snapshot = try core.checkpoint(for: session)
        persistence.save(session, scope: scope, checkpoint: snapshot)
    }

    private func reconcileStores(after previous: BrowserSession, from source: BrowserStore?) {
        stores.removeAll { $0.value == nil }
        for store in stores.compactMap(\.value) {
            store.receiveFamilySessionChange(
                from: previous, to: authoritativeSession, adoptingSelection: store === source
            )
        }
        borrowedFamilies.removeAll { $0.value == nil }
        for child in borrowedFamilies.compactMap(\.value) { _ = child.refreshBorrowed() }
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

    /// Defence in depth for locked Spaces. The UI already refuses to reach one,
    /// but after this the core's own records reject any command that would read
    /// or write a Space this process holds no access grant for.
    func attachSpaceAccess(_ controller: BrowserSpaceAccessController) {
        do { try core.attachAccess(controller.coreAccess) }
        catch { preconditionFailure("Cannot attach Space access to the core session: \(error)") }
    }

    func beginDeletingSpace(_ id: SpaceID) -> Bool {
        activeSpaceDeletions.insert(id).inserted
    }

    func isActivelyDeletingSpace(_ id: SpaceID) -> Bool { activeSpaceDeletions.contains(id) }

    func finishDeletingSpace(_ id: SpaceID) {
        activeSpaceDeletions.remove(id)
    }

    func resetDeletionState() {
        activeSpaceDeletions.removeAll()
    }
}
