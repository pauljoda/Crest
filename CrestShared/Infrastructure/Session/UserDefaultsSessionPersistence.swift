import Dispatch
import Foundation

/// Splits the durable session into a light core, per-Space history, and a favicon
/// side store, so a trivial mutation stops re-encoding the whole graph.
///
/// - `crest.session.v2` holds the session *core*: every Space with its tabs,
///   archived tabs, folders, branding, and preferences — but with each history
///   list empty and each `faviconData` absent.
/// - `crest.history.v1.<spaceID>` holds one Space's history, so a visit rewrites
///   that Space alone. `crest.history.v1.index` records which Spaces have a key,
///   which is how a deleted Space's history stops being stored.
/// - Favicons live in `faviconStore`, keyed by tab.
///
/// The core is still `BrowserSession`'s own JSON, so the legacy blob and the core
/// decode through one path and the split stays invisible to the rest of the app:
/// `load()` joins history and favicons back onto the session it hands out, and
/// every caller keeps reading `tab.faviconData` and `space.history`.
final class UserDefaultsBrowserSessionPersistence: BrowserSessionPersisting, @unchecked Sendable {
    typealias Encoder = @Sendable (BrowserSession) -> Data?
    typealias Publisher = @Sendable (UserDefaults, String, Data) -> Void
    typealias Remover = @Sendable (UserDefaults, String) -> Void

    /// The session core. Bumped from v1 because v1 blobs carry history and
    /// favicon bytes this layout deliberately no longer stores here.
    static let coreKey = "crest.session.v2"
    /// The whole-graph blob every release before the split wrote. Read once, at
    /// the migration, and never written again.
    static let legacyCoreKey = "crest.session.v1"
    static let historyKeyPrefix = "crest.history.v1."
    /// The Spaces that may own a history key. Kept so a Space that goes away
    /// takes its history with it without scanning the whole defaults domain.
    static let historyIndexKey = "crest.history.v1.index"
    /// Set once the legacy blob has been split. Informational: the decision to
    /// migrate is made by the absence of a core, so a half-finished migration
    /// simply runs again. The next release reads this to retire v1.
    static let legacyMigrationKey = "crest.session.migratedToV2"
    /// Where a core that refused to decode is copied before anything writes over
    /// it. A rollback, a second Mac, or a truncated write can leave a payload
    /// this build cannot read but a later one can, so the bytes outlive the
    /// launch that could not use them.
    static let preservedCoreKey = "crest.session.unreadable.v2"
    /// The same rescue for the pre-split blob. Migration never rewrites v1, so
    /// this exists to make an unreadable legacy blob *findable* rather than to
    /// protect it from being overwritten.
    static let preservedLegacyCoreKey = "crest.session.unreadable.v1"

    static func historyKey(for spaceID: SpaceID) -> String {
        historyKeyPrefix + spaceID.rawValue.uuidString
    }

    private let defaults: UserDefaults
    private let faviconStore: any BrowserFaviconStoring
    private let encoder: Encoder
    private let publisher: Publisher
    private let remover: Remover
    private let saveQueue: DispatchQueue

    /// The newest session handed to `save`, so a `load()` racing a save sees it
    /// rather than whatever `UserDefaults` has caught up to — the job
    /// `latestEncodedData` used to do, for a fraction of the memory: this shares
    /// storage with the session the store is already holding.
    private var latestSession: BrowserSession?
    /// The core and the per-Space history last written, so a save that changed
    /// nothing neither encodes nor writes. Compared by value rather than by
    /// encoded bytes because `JSONEncoder` promises no key order for a
    /// synthesized `Codable`: two encodings of one value differ in layout, and a
    /// byte comparison would call every save a change.
    private var lastWrittenCore: BrowserSession?
    private var lastWrittenHistory: [SpaceID: [BrowserHistoryEntry]] = [:]
    /// Spaces believed to own a history key, seeded from `historyIndexKey`.
    private var indexedSpaceIDs: Set<SpaceID>?
    /// Live tabs believed to own a favicon. A core write that finds this set
    /// shrinking is what schedules a favicon sweep.
    private var storedFaviconTabIDs: Set<TabID>?
    /// What the last `load()` found. Lives on `saveQueue` with the rest of the
    /// store's state, so the flag the save path reads and the status a composition
    /// root reads can never disagree.
    private var loadStatus: BrowserSessionPersistenceStatus = .ready

    /// What the last `load()` found. A composition root reads this after `load()`
    /// to tell "new installation" apart from "the stored session is unreadable
    /// and has been set aside".
    var status: BrowserSessionPersistenceStatus {
        saveQueue.sync { loadStatus }
    }

    init(
        defaults: UserDefaults = .standard,
        faviconStore: any BrowserFaviconStoring = BrowserFaviconFileStore.production()
            ?? InMemoryBrowserFaviconStore(),
        encoder: @escaping Encoder = { try? JSONEncoder().encode($0) },
        publisher: @escaping Publisher = { defaults, key, data in
            defaults.set(data, forKey: key)
        },
        remover: @escaping Remover = { defaults, key in
            defaults.removeObject(forKey: key)
        }
    ) {
        self.defaults = defaults
        self.faviconStore = faviconStore
        self.encoder = encoder
        self.publisher = publisher
        self.remover = remover
        saveQueue = DispatchQueue(
            label: "com.pauldavis.crest.session-persistence",
            qos: .utility
        )
    }

    func load() -> BrowserSession? {
        if let pending = saveQueue.sync(execute: { latestSession }) {
            return pending
        }
        if let session = storedSession() {
            return session
        }
        return migratedLegacySession()
    }

    func save(_ session: BrowserSession, scope: BrowserSessionSaveScope) {
        saveQueue.async { [self] in
            latestSession = session
            var writes: [(key: String, data: Data)] = []
            var removals: [String] = []

            if scope.writesCore {
                let core = Self.core(of: session)
                if core != lastWrittenCore, let data = encoder(core) {
                    lastWrittenCore = core
                    writes.append((Self.coreKey, data))
                }
                reconcileHistoryIndex(for: session, writes: &writes, removals: &removals)
            }
            for space in session.spaces where scope.history.covers(space.id) {
                guard space.history != lastWrittenHistory[space.id],
                    let data = try? JSONEncoder().encode(space.history)
                else { continue }
                lastWrittenHistory[space.id] = space.history
                writes.append((Self.historyKey(for: space.id), data))
            }
            if scope.writesCore || scope.favicons != .nothing {
                reconcileFavicons(for: session, scope: scope)
            }

            guard !writes.isEmpty || !removals.isEmpty else { return }
            DispatchQueue.main.async { [self] in
                for write in writes {
                    publisher(defaults, write.key, write.data)
                }
                for removal in removals {
                    remover(defaults, removal)
                }
            }
        }
    }

    func flushPendingSaves() async {
        await withCheckedContinuation { continuation in
            saveQueue.async {
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
        await faviconStore.flushPendingWrites()
    }

    // MARK: - Recovery

    /// The bytes of a session this build could not read, kept for a build that
    /// can. Nothing in the app requires them; they exist so an unreadable
    /// session is a recoverable incident rather than a deletion.
    func preservedUnreadableSessionData() -> Data? {
        defaults.data(forKey: Self.preservedCoreKey)
            ?? defaults.data(forKey: Self.preservedLegacyCoreKey)
    }

    /// Drops the set-aside copy. Only a caller that has finished with those bytes
    /// may call this; until then the copy is the only remaining record of the
    /// session that would not decode.
    func discardPreservedUnreadableSession() {
        remover(defaults, Self.preservedCoreKey)
        remover(defaults, Self.preservedLegacyCoreKey)
    }

    // MARK: - Loading

    private func storedSession() -> BrowserSession? {
        guard let data = defaults.data(forKey: Self.coreKey) else { return nil }
        guard var session = try? JSONDecoder().decode(BrowserSession.self, from: data) else {
            // Absence and failure are not the same answer. Only absence means
            // "new installation", and only failure has bytes worth keeping.
            preserveUnreadable(data, as: Self.preservedCoreKey)
            return nil
        }
        // Only history that was stored inside the cap is remembered as written:
        // an overflowing key from an older layout is left to the next save of
        // that Space to trim.
        var storedHistory: [SpaceID: [BrowserHistoryEntry]] = [:]
        for spaceIndex in session.spaces.indices {
            let spaceID = session.spaces[spaceIndex].id
            if let historyData = defaults.data(forKey: Self.historyKey(for: spaceID)) {
                let history = Self.decodedHistory(historyData)
                session.spaces[spaceIndex].history = history.capped
                if !history.wasTrimmed {
                    storedHistory[spaceID] = history.capped
                }
            } else {
                session.spaces[spaceIndex].history = []
                storedHistory[spaceID] = []
            }
            for tabIndex in session.spaces[spaceIndex].tabs.indices {
                let tabID = session.spaces[spaceIndex].tabs[tabIndex].id
                session.spaces[spaceIndex].tabs[tabIndex].faviconData =
                    faviconStore.favicon(tabID: tabID)
            }
        }
        adoptLoadedState(session, storedHistory: storedHistory)
        return session
    }

    /// Splits the legacy whole-graph blob into the new stores.
    ///
    /// The blob is left in place for one release. It is a free rollback, and it
    /// is what makes a crash between here and the first core write cost nothing:
    /// no core means the next launch migrates again.
    private func migratedLegacySession() -> BrowserSession? {
        guard let data = defaults.data(forKey: Self.legacyCoreKey) else { return nil }
        guard let session = try? JSONDecoder().decode(BrowserSession.self, from: data) else {
            preserveUnreadable(data, as: Self.preservedLegacyCoreKey)
            return nil
        }
        save(session, scope: .everything)
        defaults.set(true, forKey: Self.legacyMigrationKey)
        return session
    }

    /// Copies an unreadable payload aside and puts the store into the mode where
    /// it deletes nothing.
    ///
    /// The copy is written synchronously, on the way out of `load()`, because the
    /// caller's very next move is to seed a session and save it. An existing copy
    /// is never replaced: the first rescue is the one closest to the person's real
    /// session, and a later launch that only ever saw the seed must not overwrite
    /// it with the seed's own corruption.
    private func preserveUnreadable(_ data: Data, as key: String) {
        if defaults.data(forKey: key) == nil {
            publisher(defaults, key, data)
        }
        saveQueue.async { [self] in
            loadStatus = .preservedUnreadableSession
        }
    }

    /// Teaches the save path what is already stored, so the full save every
    /// launch performs rewrites only what launch repair actually changed, and
    /// sweeps any favicon a crash left behind.
    private func adoptLoadedState(
        _ session: BrowserSession,
        storedHistory: [SpaceID: [BrowserHistoryEntry]]
    ) {
        let core = Self.core(of: session)
        let tabIDs = Self.faviconOwningTabIDs(of: session)
        saveQueue.async { [self] in
            lastWrittenCore = core
            lastWrittenHistory = storedHistory
            storedFaviconTabIDs = tabIDs
        }
        faviconStore.pruneFavicons(keeping: tabIDs)
    }

    private static func decodedHistory(
        _ data: Data
    ) -> (capped: [BrowserHistoryEntry], wasTrimmed: Bool) {
        guard let history = try? JSONDecoder().decode([BrowserHistoryEntry].self, from: data) else {
            return ([], false)
        }
        let capped = Array(history.prefix(BrowserSession.maximumHistoryEntriesPerSpace))
        return (capped, capped.count != history.count)
    }

    // MARK: - Saving

    /// The session without the two things that made every save expensive.
    private static func core(of session: BrowserSession) -> BrowserSession {
        var core = session
        for spaceIndex in core.spaces.indices {
            core.spaces[spaceIndex].history = []
            for tabIndex in core.spaces[spaceIndex].tabs.indices {
                core.spaces[spaceIndex].tabs[tabIndex].faviconData = nil
            }
            for archiveIndex in core.spaces[spaceIndex].archivedTabs.indices {
                core.spaces[spaceIndex].archivedTabs[archiveIndex].tab.faviconData = nil
            }
        }
        return core
    }

    private static func faviconOwningTabIDs(of session: BrowserSession) -> Set<TabID> {
        Set(session.spaces.flatMap { $0.tabs.map(\.id) })
    }

    /// Keeps the history index in step with the Spaces that exist, and removes
    /// the history of Spaces that no longer do. Runs on every core write, which
    /// is what makes a Space deletion drop its history promptly.
    private func reconcileHistoryIndex(
        for session: BrowserSession,
        writes: inout [(key: String, data: Data)],
        removals: inout [String]
    ) {
        // An unreadable core means the Spaces that own history are unknown. The
        // session being saved is whatever the caller could assemble without them
        // — very likely a fresh-install seed — so reconciling against it would
        // read "every previous Space is gone" and remove its history for real.
        guard loadStatus != .preservedUnreadableSession else { return }
        let spaceIDs = Set(session.spaces.map(\.id))
        let previous = indexedSpaceIDs ?? storedHistoryIndex()
        indexedSpaceIDs = spaceIDs
        guard previous != spaceIDs else { return }
        for removed in previous.subtracting(spaceIDs) {
            removals.append(Self.historyKey(for: removed))
            lastWrittenHistory[removed] = nil
        }
        guard
            let data = try? JSONEncoder().encode(
                spaceIDs.map(\.rawValue.uuidString).sorted()
            )
        else { return }
        writes.append((Self.historyIndexKey, data))
    }

    private func storedHistoryIndex() -> Set<SpaceID> {
        guard let data = defaults.data(forKey: Self.historyIndexKey),
            let identifiers = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return Set(identifiers.compactMap(UUID.init(uuidString:)).map(SpaceID.init(rawValue:)))
    }

    private func reconcileFavicons(
        for session: BrowserSession,
        scope: BrowserSessionSaveScope
    ) {
        for space in session.spaces {
            for tab in space.tabs where scope.favicons.covers(tab.id) {
                faviconStore.reconcile(tab.faviconData, tabID: tab.id)
            }
        }
        // Same reasoning as the history index: a sweep keyed to a session that
        // was assembled without the unreadable core would delete every icon that
        // core still owns.
        guard loadStatus != .preservedUnreadableSession else { return }
        guard scope.writesCore || scope.favicons.isEverything else { return }
        let tabIDs = Self.faviconOwningTabIDs(of: session)
        defer { storedFaviconTabIDs = tabIDs }
        // Only a shrinking set can orphan a favicon, and comparing sets in
        // memory keeps the common save free of any directory listing.
        guard let previous = storedFaviconTabIDs, !tabIDs.isSuperset(of: previous) else { return }
        faviconStore.pruneFavicons(keeping: tabIDs)
    }
}
