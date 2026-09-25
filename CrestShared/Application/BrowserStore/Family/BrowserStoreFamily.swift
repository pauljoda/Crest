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
    /// The session every window of this family followed last, which they
    /// follow from when the next change to it reaches them.
    @ObservationIgnored private var followedSession: BrowserSession
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

    /// Whether the core still holds this family's workspace open. A borrowed
    /// one closes once its owner no longer lends its Space.
    var isOpen: Bool { core.isOpen }

    /// A family over a workspace `crest` opens in memory from `session`, of
    /// the kind `browsingMode` browses in. It keeps nothing: it is never saved
    /// or synced.
    convenience init(session: BrowserSession, browsingMode: BrowserBrowsingMode = .standard, core crest: CrestCore) {
        let kind: WorkspaceKind = browsingMode.isPrivate ? .private : .persistent
        do {
            self.init(memory: try BrowserCoreSessionAuthority.open(kind, seed: session, in: crest))
        } catch {
            preconditionFailure("The core refused to open a workspace over a session it was given: \(error)")
        }
    }

    /// A family over a new private workspace in `crest`, which starts from the
    /// core's private template.
    convenience init(privateIn crest: CrestCore) {
        do {
            self.init(memory: try BrowserCoreSessionAuthority.open(.private, seed: nil, in: crest))
        } catch {
            preconditionFailure("The core refused to open a private workspace: \(error)")
        }
    }

    private init(memory core: BrowserCoreSessionAuthority) {
        self.core = core
        followedSession = core.projection
        temporarySourceAssignment = nil
        temporarySettingsBrowser = nil
        storage = nil
        favicons = nil
        followSession()
    }

    /// The family of the session `storage` keeps in its file, opened by
    /// `stored`. Every image the loaded session carries is reconciled with
    /// `favicons`, and images of tabs it no longer has are pruned, as each
    /// later edit does for what it changed.
    init(stored: BrowserCoreSessionAuthority, storage: CrestCore, favicons: any BrowserFaviconStoring) {
        core = stored
        followedSession = stored.projection
        temporarySourceAssignment = nil
        temporarySettingsBrowser = nil
        self.storage = storage
        self.favicons = favicons
        let tabs = stored.projection.spaces.flatMap(\.tabs)
        for tab in tabs { favicons.reconcile(tab.faviconData, tabID: tab.id) }
        favicons.pruneFavicons(keeping: Set(tabs.map(\.id)))
        storage.storageFailureHandler = { [weak self] reason in self?.storageDidFail(reason) }
        followSession()
    }

    private init(
        core: BrowserCoreSessionAuthority, assignment: BrowserSpaceRuntimeAssignment, settingsBrowser: BrowserStore
    ) {
        self.core = core
        temporarySourceAssignment = assignment
        temporarySettingsBrowser = settingsBrowser
        followedSession = core.projection
        storage = nil
        favicons = nil
        followSession()
    }

    /// A family over a workspace that borrows the Space `assignment` names
    /// from this family's workspace, whose settings `settingsBrowser` edits.
    func makeBorrowed(in assignment: BrowserSpaceRuntimeAssignment, settingsBrowser: BrowserStore) throws
        -> BrowserStoreFamily
    {
        let child = BrowserStoreFamily(
            core: try core.borrow(assignment),
            assignment: assignment, settingsBrowser: settingsBrowser)
        borrowedFamilies.removeAll { $0.value == nil }
        borrowedFamilies.append(WeakFamily(value: child))
        return child
    }

    /// Closes this family's workspace, and first every workspace that borrows
    /// from it. Its windows close in the core, which keeps their saved
    /// records. Closing it again does nothing.
    func close() {
        core.close()
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
            let dataDeleter = spaceDataDeleter, let store = spaceCleanupStore
        else { return }
        spaceCleanupTask = Task { [weak self] in
            await store.resumePendingSpaceDeletions(dataDeleter: dataDeleter)
            self?.spaceCleanupTask = nil
        }
    }

    /// Temporary tabs retain their own organization, but profile identity and
    /// privacy always read through to their source, including during deletion.
    /// A borrowed workspace the core closed shows no Space.
    var currentSession: BrowserSession {
        guard let assignment = temporarySourceAssignment, let source = temporarySettingsBrowser else {
            return authoritativeSession
        }
        var current = authoritativeSession
        guard core.isOpen, source.space(matching: assignment) != nil else {
            current.spaces = []
            return current
        }
        return current
    }

    /// The workspace the core gave this family's session.
    var workspaceID: UUID { core.workspaceID }

    /// Adds a window of this family, and answers the workspace it shows. A
    /// session shows in the windows of the one core that opened it.
    func register(_ store: BrowserStore) -> UUID {
        guard core.device === store.core else {
            preconditionFailure("A session shows in the windows of the core that opened it.")
        }
        stores.removeAll { $0.value == nil }
        stores.append(WeakStore(value: store))
        return core.workspaceID
    }

    /// Takes records the cloud sent through `intent`, which the core saves
    /// with its journal before it returns. What it changed arrives in the drain
    /// that follows, which every window follows and which starts the cleanup of
    /// a Space the cloud deleted. Throws the rule that refused the records or
    /// the save that failed; either changes nothing.
    ///
    /// TRANSITIONAL until the cloud transport sends its intents itself.
    func commitCloudRecords(_ intent: some CloudSyncIntent, from source: BrowserStore) throws(Rejection) {
        try source.core.send(intent)
        source.core.drain()
    }

    /// Runs an import `source`'s window issued, which the core saves with its
    /// journal before it returns. Each tab it places wears the image its tab in
    /// `sources`, the Spaces the import brings, wears. Throws the rule that
    /// refused it or the save that failed; either changes nothing.
    func importSpaces(_ intent: some ImportWorkspace, from sources: [BrowserSpace], issuedBy source: BrowserStore)
        throws(Rejection)
    {
        let previous = authoritativeSession
        let favicons = source.core.state.favicons
        favicons.offer(FaviconAssets.Offer(importing: sources), in: workspaceID)
        defer { favicons.withdrawOffer(in: workspaceID) }
        _ = try source.core.send(intent)
        guard authoritativeSession != previous else { return }
        follow()
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
        follow()
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
        follow()
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

    /// Moves a tab from `source`'s window to `destination`'s. The core changes
    /// both workspaces together, saving the one that keeps a file with its
    /// journal before it returns, and the windows of both families follow,
    /// even when only what they show changed.
    static func moveTab(
        _ intent: MoveTabToWindow, from source: BrowserStore, to destination: BrowserStore
    ) throws(Rejection) {
        try source.core.send(intent)
        source.family.follow(always: true)
        guard destination.family !== source.family else { return }
        destination.family.follow(always: true)
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

    /// Every window follows the accepted session. The core's device already
    /// moved the window that issued the command and repaired the others, and
    /// the session copy already holds what the core published for it.
    private func reconcileStores(after previous: BrowserSession) {
        persistFavicons(from: previous, to: authoritativeSession)
        followedSession = authoritativeSession
        stores.removeAll { $0.value == nil }
        for store in stores.compactMap(\.value) {
            store.receiveFamilySessionChange(from: previous, to: authoritativeSession)
        }
        borrowedFamilies.removeAll { $0.value == nil }
        for child in borrowedFamilies.compactMap(\.value) { child.follow() }
    }

    /// Every window follows the accepted session from the one they followed
    /// last, which keeps the images tabs took beside the session file. Unless
    /// `always`, nothing happens while they already follow it.
    private func follow(always: Bool = false) {
        let previous = followedSession
        guard always || authoritativeSession != previous else { return }
        reconcileStores(after: previous)
    }

    /// Hears each batch of the core's changes that changed this family's
    /// session or its sync journal: a page's navigation or icon it recorded, a
    /// cloud merge, or the changes an intent answered. Every window follows,
    /// and a Space deletion whose cleanup has not finished starts it again.
    /// TRANSITIONAL until S6.
    private func followSession() {
        core.device?.followSessions(self) { [weak self] workspaces in
            guard let self, workspaces.contains(workspaceID) else { return }
            follow()
            scheduleSpaceDataCleanup()
        }
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
