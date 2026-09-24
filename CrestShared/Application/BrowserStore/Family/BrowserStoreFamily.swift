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
    private var activeSpaceDeletions: Set<SpaceID> = []
    var deletingSpaceIDs: Set<SpaceID> {
        activeSpaceDeletions.union(authoritativeSession.spaceDeletions?.map(\.spaceID) ?? [])
    }
    @ObservationIgnored private weak var spaceDataDeleter: (any BrowserSpaceDataDeleting)?
    @ObservationIgnored private weak var spaceCleanupStore: BrowserStore?
    @ObservationIgnored private(set) var spaceCleanupTask: Task<Void, Never>?
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
        observePageRecords()
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
        observePageRecords()
    }

    private init(core: BrowserCoreSessionAuthority, assignment: BrowserSpaceRuntimeAssignment, settingsBrowser: BrowserStore) {
        self.core = core; temporarySourceAssignment = assignment; temporarySettingsBrowser = settingsBrowser
        storage = nil
        favicons = nil
        observePageRecords()
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

    /// The workspace the core's device gave this family's session.
    var workspaceID: UUID {
        guard let workspace = core.workspaceID else {
            preconditionFailure("A family's session joins its core's device when the family is made.")
        }
        return workspace
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

    func importWorkspace(_ request: BrowserCoreWorkspaceImport.Request, from source: BrowserStore) throws {
        let previous = authoritativeSession
        let command = try core.prepareWorkspace(request, window: source.windowID.rawValue)
        try commitPreparedChange(command, previous: previous, from: source)
    }

    /// Commits a prepared command whose failure the caller handles. The core
    /// saves an import and a cross-Space move with the journal it stages
    /// before this returns, because an upload follows.
    private func commitPreparedChange(_ command: BrowserCoreSessionAuthority.PreparedChange,
        previous: BrowserSession, from source: BrowserStore) throws {
        try core.commit(command)
        reconcileStores(after: previous, from: source)
    }

    /// Runs one session intent that `source`'s window issued. What it changed
    /// reaches the session copy and the read model through the core's changes,
    /// and every window then follows the accepted session. Answers whether the
    /// session changed; a refusal changes nothing, and the window's sync
    /// status reports it after `failure`.
    @discardableResult
    func send(
        _ intent: some Intent, from source: BrowserStore, offering image: Data? = nil,
        failure: String = "Core command failed"
    ) -> Bool {
        perform(intent, from: source, offering: image, failure: failure)?.changed ?? false
    }

    /// Runs one session intent as `send` does, and answers the changes the
    /// core published with it and whether the session changed, or nil when a
    /// rule refused it. `image` is the image `source` holds for the tab the
    /// core tells to adopt its issuer's, such as a favicon pulled from a page.
    func perform(
        _ intent: some Intent, from source: BrowserStore, offering image: Data? = nil,
        failure: String = "Core command failed"
    ) -> (changes: [Change], changed: Bool)? {
        let previous = authoritativeSession
        let changes: [Change]
        let favicons = source.core.state.favicons
        if let image { favicons.offer(FaviconAssets.Offer(assigned: image), in: workspaceID) }
        defer { if image != nil { favicons.withdrawOffer(in: workspaceID) } }
        do {
            changes = try source.core.send(intent)
        } catch {
            source.localSyncErrorDescription = "\(failure): \(error)"
            return nil
        }
        guard authoritativeSession != previous else { return (changes, false) }
        reconcileStores(after: previous, from: source)
        return (changes, true)
    }

    /// Runs one session intent as `send` does, and answers the changes the
    /// core published with it, or throws the rule that refused it or the save
    /// that failed, for a caller that handles either, such as a deletion step
    /// the core saves before it returns.
    @discardableResult
    func commit(_ intent: some Intent, from source: BrowserStore) throws(Rejection) -> [Change] {
        let previous = authoritativeSession
        let changes = try source.core.send(intent)
        guard authoritativeSession != previous else { return changes }
        reconcileStores(after: previous, from: source)
        return changes
    }

    /// Whether the core would accept a session intent `source`'s window
    /// issues, asked without changing anything. This is how menus ask the
    /// core's rules, such as a folder's depth or a split's size, instead of
    /// keeping copies of them.
    func canSend(_ intent: some Intent, from source: BrowserStore) -> Bool {
        guard let permission = try? source.core.query(CanSend(intent: intent)) else { return false }
        return permission.refusal == nil
    }

    /// The rule that would refuse a session intent `source`'s window issues,
    /// asked without changing anything, or nil when the core would accept it
    /// or could not answer.
    func refusal(of intent: some Intent, from source: BrowserStore) -> Rejection? {
        (try? source.core.query(CanSend(intent: intent)))?.refusal
    }

    func moveTab(_ tabID: TabID, source: BrowserSpaceRuntimeAssignment, destination: BrowserSpaceRuntimeAssignment,
        arguments: BrowserCoreTabTransfer.Arguments, from store: BrowserStore, at date: Date) throws {
        let previous = authoritativeSession
        let command = try core.prepareTabMove(tabID, source: source, destination: destination,
            arguments: arguments, window: store.windowID.rawValue, at: date)
        try commitPreparedChange(command, previous: previous, from: store)
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
        // The core saves the persistent side with the journal it stages before
        // either side is published; the temporary side keeps nothing.
        try BrowserCoreSessionAuthority.commitTransfer(prepared, source: source.family.core,
            destination: destination.family.core)
        source.family.reconcileStores(after: previousSource, from: source)
        destination.family.reconcileStores(after: previousDestination, from: destination)
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

    /// Hears what the core records from the pages of this family's workspace,
    /// which changes the session without a command of the family's.
    private func observePageRecords() {
        core.device?.engines.observeRecords(self) { [weak self] in self?.pageRecordsApplied($0) }
    }

    /// The core recorded a page's navigation or gave a tab its page's icon:
    /// the images tabs took are kept beside the session file, and every window
    /// reconciles with the session as it does after a command.
    private func pageRecordsApplied(_ records: Engines.PageRecords) {
        guard let workspace = core.workspaceID,
            records.navigations.contains(where: { $0.workspaceID == workspace })
                || records.icons.contains(where: { $0.workspaceID == workspace })
        else { return }
        let session = authoritativeSession
        if let favicons {
            let adopted = Set(records.icons.filter { $0.workspaceID == workspace }.map(\.tabID))
            for tab in session.spaces.flatMap(\.tabs) where adopted.contains(tab.id.rawValue) {
                favicons.reconcile(tab.faviconData, tabID: tab.id)
            }
        }
        stores.removeAll { $0.value == nil }
        for store in stores.compactMap(\.value) { store.receiveFamilySessionChange(from: session, to: session) }
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
