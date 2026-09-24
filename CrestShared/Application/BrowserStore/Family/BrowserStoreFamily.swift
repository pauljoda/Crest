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
    /// The core that keeps this family's session in its file; nil in memory.
    @ObservationIgnored private let storage: CrestCore?
    /// Where tab images are kept beside the session file; nil in memory.
    @ObservationIgnored private let favicons: (any BrowserFaviconStoring)?

    /// Whether this family's windows keep their records across launches:
    /// only the windows over the session the core keeps in its file do.
    var keepsWindowRecords: Bool { storage != nil }

    /// A family over a memory-only session, which `crest`'s windows show.
    init(
        session: BrowserSession, browsingMode: BrowserBrowsingMode = .standard,
        temporarySourceAssignment: BrowserSpaceRuntimeAssignment? = nil,
        temporarySettingsBrowser: BrowserStore? = nil, core crest: CrestCore
    ) {
        precondition(temporarySourceAssignment == nil, "Borrowed workspaces must be created by their core owner")
        core = BrowserCoreSessionAuthority(session: session,
            workspaceKind: browsingMode.isPrivate ? .private : .persistent,
            privateBrowsing: browsingMode.isPrivate, core: crest)
        self.temporarySourceAssignment = temporarySourceAssignment
        self.temporarySettingsBrowser = temporarySettingsBrowser
        storage = nil
        favicons = nil
    }

    /// The family of the session `storage` keeps in its file. Every image the
    /// loaded session carries is reconciled with `favicons`, and images of tabs
    /// it no longer has are pruned, as each later edit does for what it changed.
    init(stored: BrowserCoreStoredSession, storage: CrestCore, favicons: any BrowserFaviconStoring) {
        core = stored.authority
        temporarySourceAssignment = nil
        temporarySettingsBrowser = nil
        self.storage = storage
        self.favicons = favicons
        let tabs = stored.authority.projection.spaces.flatMap(\.tabs)
        for tab in tabs { favicons.reconcile(tab.faviconData, tabID: tab.id) }
        favicons.pruneFavicons(keeping: Set(tabs.map(\.id)))
        storage.storageFailureHandler = { [weak self] reason in self?.storageDidFail(reason) }
    }

    private init(core: BrowserCoreSessionAuthority, assignment: BrowserSpaceRuntimeAssignment, settingsBrowser: BrowserStore) {
        self.core = core; temporarySourceAssignment = assignment; temporarySettingsBrowser = settingsBrowser
        storage = nil
        favicons = nil
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

    /// Adds a window of this family, and answers the workspace it shows. A
    /// session shows in the windows of the one core it was attached to.
    func register(_ store: BrowserStore) -> UUID {
        if let sync = store.syncCoordinator {
            do { try core.attachSync(sync.core) }
            catch { preconditionFailure("Cannot attach sync to the core session: \(error)") }
        }
        guard let workspace = core.workspaceID, core.device === store.core else {
            preconditionFailure("A session shows in the windows of the core it was attached to.")
        }
        stores.removeAll { $0.value == nil }
        stores.append(WeakStore(value: store))
        return workspace
    }

    #if DEBUG
        func replaceSessionForTesting(_ session: BrowserSession, from source: BrowserStore) {
            let previous = authoritativeSession
            do {
                try core.replaceDurably(with: session)
            } catch {
                source.localSyncErrorDescription = "Core test session update failed: \(error)"
                return
            }
            reconcileStores(after: previous, from: source)
        }
    #endif

    /// An incoming merge: the core saves the session and its journal together
    /// before either is published.
    func installSyncedSession(
        _ session: BrowserSession, transaction: BrowserCoreSyncTransaction, from source: BrowserStore
    ) throws {
        let previous = authoritativeSession
        try core.replaceDurably(with: session, sync: transaction)
        reconcileStores(after: previous, from: source)
        scheduleSpaceDataCleanup()
    }

    func executeSpace<Arguments: Encodable>(_ operation: BrowserSessionOperation, in spaceID: SpaceID? = nil,
        arguments: Arguments, from source: BrowserStore, at date: Date = .now) -> Bool {
        let previous = authoritativeSession
        let shown = source.window
        do {
            try core.executeSpace(operation, in: spaceID, arguments: arguments, window: source.windowID.rawValue, at: date)
            reconcileStores(after: previous, from: source)
            return authoritativeSession != previous || source.window != shown
        } catch {
            source.localSyncErrorDescription = "Core Space command failed: \(error)"
            return false
        }
    }

    func executeSpaceDurably<Arguments: Encodable>(_ operation: BrowserSessionOperation, in spaceID: SpaceID,
        arguments: Arguments, deletionReason: BrowserSyncTombstoneReason = .superseded, from source: BrowserStore,
        at date: Date = .now) throws {
        let previous = authoritativeSession
        let command = try core.prepareSpace(
            operation, in: spaceID, arguments: arguments, window: source.windowID.rawValue, at: date)
        try commitPreparedChange(command, previous: previous, deletionReason: deletionReason, from: source, at: date)
    }

    func importWorkspace(_ request: BrowserCoreWorkspaceImport.Request, from source: BrowserStore) throws {
        let previous = authoritativeSession
        let command = try core.prepareWorkspace(request, window: source.windowID.rawValue)
        try commitPreparedChange(command, previous: previous, deletionReason: .superseded, from: source, at: .now)
    }

    func prepareTabBatch(_ request: BrowserTabBatchRequest, arguments: BrowserCoreTabBatch.Arguments, from store: BrowserStore,
        at date: Date) throws -> (command: BrowserCoreSessionAuthority.PreparedChange, result: BrowserTabBatchResult) {
        try core.prepareTabBatch(request, arguments: arguments, window: store.windowID.rawValue, at: date)
    }

    func commitTabBatch(_ command: BrowserCoreSessionAuthority.PreparedChange,
        deletionReason: BrowserSyncTombstoneReason, from store: BrowserStore, at date: Date) throws {
        try commitPreparedChange(command, previous: authoritativeSession, deletionReason: deletionReason, from: store, at: date)
    }

    /// Space deletion, import, batches and cross-Space moves: the command and
    /// the journal it stages are saved together before the command returns,
    /// because an upload follows and Space deletion erases engine data between
    /// its two commands.
    private func commitPreparedChange(_ command: BrowserCoreSessionAuthority.PreparedChange,
        previous: BrowserSession, deletionReason: BrowserSyncTombstoneReason, from source: BrowserStore, at date: Date) throws {
        let revision = reserveSyncRevision()
        if let sync = source.syncCoordinator {
            sync.advanceStoreRevision(to: revision)
            try sync.installLocalCommand(command.session, deletionReason: deletionReason, at: date, revision: revision) {
                _, transaction in
                try self.core.commitDurably(command, sync: transaction)
            }
        } else {
            try core.commitDurably(command)
        }
        reconcileStores(after: previous, from: source)
        source.cloudSyncChangeHandler?()
    }

    /// App-wide behavior preferences. Only the preference record changes, so
    /// every window keeps showing what it showed.
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
    func readCore<Request: Encodable>(_ request: Request) -> Data? { try? core.read(request) }

    /// Runs a tab, folder or split command. `image` is the image a page
    /// reported, which the tab the core assigns it to wears.
    func execute<Arguments: Encodable>(_ operation: BrowserSessionOperation, in spaceID: SpaceID,
        arguments: Arguments, from source: BrowserStore, at date: Date, image: Data? = nil)
        -> BrowserCoreSessionEditing.Result? {
        let previous = authoritativeSession
        do {
            let result = try core.execute(
                operation, in: spaceID, arguments: arguments, window: source.windowID.rawValue, at: date, image: image)
            reconcileStores(after: previous, from: source)
            return result
        } catch {
            source.localSyncErrorDescription = "Core command failed: \(error)"
            return nil
        }
    }

    /// A record command without arguments of its own.
    func executeRecords(_ operation: BrowserSessionOperation, in spaceID: SpaceID? = nil,
        from source: BrowserStore, at date: Date = .now) -> Bool {
        executeRecords(operation, in: spaceID, arguments: BrowserCoreNoArguments(), from: source, at: date)
    }

    func executeRecords<Arguments: Encodable>(_ operation: BrowserSessionOperation, in spaceID: SpaceID? = nil,
        arguments: Arguments, from source: BrowserStore, at date: Date = .now) -> Bool {
        let previous = authoritativeSession
        do {
            let changed = try core.executeRecords(
                operation, in: spaceID, arguments: arguments, window: source.windowID.rawValue, at: date)
            if changed { reconcileStores(after: previous, from: source) }
            return changed
        } catch {
            source.localSyncErrorDescription = "Core record command failed: \(error)"
            return false
        }
    }

    func moveTab(_ tabID: TabID, source: BrowserSpaceRuntimeAssignment, destination: BrowserSpaceRuntimeAssignment,
        arguments: BrowserCoreTabTransfer.Arguments, from store: BrowserStore, at date: Date) throws {
        let previous = authoritativeSession
        let command = try core.prepareTabMove(tabID, source: source, destination: destination,
            arguments: arguments, window: store.windowID.rawValue, at: date)
        try commitPreparedChange(command, previous: previous, deletionReason: .superseded, from: store, at: date)
    }

    static func prepareTransfer(_ id: TabID, assignment: BrowserSpaceRuntimeAssignment,
        source: BrowserStore, destination: BrowserStore, selecting: Bool) throws -> BrowserCoreSessionAuthority.PreparedTransfer {
        try BrowserCoreSessionAuthority.prepareTransfer(source: source.family.core, sourceWindow: source.windowID.rawValue,
            destination: destination.family.core, destinationWindow: destination.windowID.rawValue,
            tabID: id, assignment: assignment, selecting: selecting)
    }

    static func transfer(_ prepared: BrowserCoreSessionAuthority.PreparedTransfer,
        source: BrowserStore, destination: BrowserStore) throws {
        let previousSource = source.family.authoritativeSession
        let previousDestination = destination.family.authoritativeSession
        let durable = source.isTemporaryWorkspace ? destination : source
        let next = source.isTemporaryWorkspace ? prepared.destination : prepared.source
        let revision = durable.family.reserveSyncRevision()
        // The core saves the persistent side with its journal before either
        // side is published; the temporary side keeps nothing.
        func commit(_ transaction: BrowserCoreSyncTransaction? = nil) throws {
            try BrowserCoreSessionAuthority.commitTransfer(prepared, source: source.family.core,
                destination: destination.family.core, sync: transaction)
        }
        if let sync = durable.syncCoordinator {
            sync.advanceStoreRevision(to: revision)
            try sync.installLocalCommand(next, deletionReason: .superseded, at: .now, revision: revision) {
                _, transaction in try commit(transaction)
            }
        } else { try commit() }
        source.family.reconcileStores(after: previousSource, from: source)
        destination.family.reconcileStores(after: previousDestination, from: destination)
        durable.cloudSyncChangeHandler?()
    }

    // MARK: - Actions - Storage

    /// Returns once every edit this family has accepted is on disk, or once a
    /// save has failed. A family in memory has nothing to wait for.
    func flushPendingSaves() async {
        await storage?.flushPendingSaves()
    }

    /// A save the core started itself failed: every window shows it the way
    /// a failed local save always has, through the sync status.
    private func storageDidFail(_ reason: StorageFailure) {
        stores.removeAll { $0.value == nil }
        for store in stores.compactMap(\.value) {
            store.localSyncErrorDescription = "The session could not be saved (\(reason))."
        }
    }

    /// Keeps the favicon store in step with the session: a tab whose image
    /// changed is written, and the images of tabs the session no longer has
    /// are pruned. A family in memory keeps images only in its session.
    private func persistFavicons(from previous: BrowserSession, to next: BrowserSession) {
        guard let favicons else { return }
        let earlier = Dictionary(
            previous.spaces.flatMap(\.tabs).map { ($0.id, $0.faviconData) }, uniquingKeysWith: { first, _ in first })
        var current: Set<TabID> = []
        for tab in next.spaces.flatMap(\.tabs) {
            current.insert(tab.id)
            if let known = earlier[tab.id], Self.sameImage(known, tab.faviconData) { continue }
            favicons.reconcile(tab.faviconData, tabID: tab.id)
        }
        if earlier.keys.contains(where: { !current.contains($0) }) { favicons.pruneFavicons(keeping: current) }
    }

    /// Whether two images are the same bytes, without reading them when they
    /// share storage.
    private static func sameImage(_ first: Data?, _ second: Data?) -> Bool {
        guard let first, let second else { return first == nil && second == nil }
        guard first.count == second.count else { return false }
        return first.withUnsafeBytes { a in
            second.withUnsafeBytes { b in
                guard let left = a.baseAddress, let right = b.baseAddress else { return true }
                return left == right || memcmp(left, right, a.count) == 0
            }
        }
    }

    /// Whether the core would accept a command in one Space, asked without
    /// committing anything.
    func accepts<Arguments: Encodable>(_ operation: BrowserSessionOperation, in spaceID: SpaceID,
        arguments: Arguments, from store: BrowserStore) -> Bool {
        core.accepts(operation, in: spaceID, arguments: arguments, window: store.windowID.rawValue)
    }

    /// Whether the core would accept moving a tab between two Spaces of this
    /// workspace, asked without committing anything.
    func acceptsTabMove(_ tabID: TabID, source: BrowserSpaceRuntimeAssignment,
        destination: BrowserSpaceRuntimeAssignment, from store: BrowserStore) -> Bool {
        core.acceptsTabMove(tabID, source: source, destination: destination, window: store.windowID.rawValue)
    }

    /// Every window follows the accepted session. The core's device already
    /// moved the window that issued the command and repaired the others, and
    /// the session copy already holds what the core published for it.
    private func reconcileStores(after previous: BrowserSession, from source: BrowserStore?) {
        persistFavicons(from: previous, to: authoritativeSession)
        stores.removeAll { $0.value == nil }
        for store in stores.compactMap(\.value) {
            store.receiveFamilySessionChange(from: previous, to: authoritativeSession)
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
