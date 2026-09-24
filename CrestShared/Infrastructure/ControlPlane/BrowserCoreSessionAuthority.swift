import CrestCoreABI
import Foundation
import Observation

/// One workspace the core opened for a store family, and the Swift copy of
/// its session. `projection` is that copy, with native favicon assets; only
/// the session changes the core publishes update it (see
/// `BrowserCoreSessionBridge.swift`), so it can never show an unaccepted edit.
/// It holds browsing data only. What each window shows is the core device's:
/// an intent names the window that issued it, and the device moves that
/// window when the intent commits and repairs the others. Nothing here names
/// a revision.
///
/// The core opens the workspace (`OpenWorkspace`, `BorrowSpace`), gives it its
/// identity and closes it (`CloseWorkspace`). Whoever owns the family closes
/// it when its windows go; a workspace no one closed closes once this copy is
/// gone.
@Observable @MainActor
final class BrowserCoreSessionAuthority {
    // MARK: - Types

    /// The images the issuer of a command holds, which `FaviconAssets` places
    /// while the core's changes for the command are applied.
    typealias OfferedImages = FaviconAssets.Offer

    /// TRANSITIONAL until slice 8a (typed sync): the edits that take the
    /// accepted records to a proposed session, as the durable replacement a
    /// sync merge commits reads them.
    private struct Delta: Encodable {
        let version = 1
        var metadata: BrowserSession?
        var spaceOrder: [UUID]?
        var spaces: [SpaceChange] = []
    }

    private struct SpaceChange: Encodable {
        let id: UUID
        var metadata: BrowserSpace?
        var tabs: CollectionEdit<BrowserTab>?
        var folders: CollectionEdit<BrowserFolder>?
        var history: CollectionEdit<BrowserHistoryEntry>?
        var archivedTabs: CollectionEdit<ArchivedTab>?

        var isEmpty: Bool {
            metadata == nil && tabs == nil && folders == nil && history == nil && archivedTabs == nil
        }
    }

    /// One collection's edit: a whole replacement, or removals, upserts and an
    /// order when the order changed.
    private enum CollectionEdit<Element: Encodable>: Encodable {
        private enum CodingKeys: String, CodingKey {
            case replace
            case remove
            case upsert
            case order
        }

        case replace([Element])
        case edit(remove: [UUID], upsert: [Element], order: [UUID]?)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .replace(let elements):
                try container.encode(elements, forKey: .replace)
            case .edit(let remove, let upsert, let order):
                try container.encode(remove, forKey: .remove)
                try container.encode(upsert, forKey: .upsert)
                try container.encodeIfPresent(order, forKey: .order)
            }
        }
    }

    private enum CoreError: Error {
        case rejected(Int32)
        /// The core could not save the commit; nothing was published.
        case storageFailed

        init(_ status: Int32) { self = status == CREST_STORAGE_FAILED ? .storageFailed : .rejected(status) }
    }

    // MARK: - Variables

    private(set) var projection: BrowserSession
    /// Whether the core still holds the workspace open. It closes when this
    /// copy closes it, when the workspace it borrows from closes or stops
    /// lending its Space, and when the core closes it for any other reason.
    private(set) var isOpen = true
    /// The workspace the core gave the session, which every change to it names.
    let workspaceID: UUID
    /// The core whose device shows this session in its windows.
    @ObservationIgnored private(set) weak var device: CrestCore?

    // MARK: - Initializers

    /// The workspace `opened` announced, whose changes reach this copy from
    /// then on. Its tabs wear the images `core` holds for them, so a caller
    /// that brings images of its own adopts them first.
    private init(opened: WorkspaceOpened, core: CrestCore) {
        workspaceID = opened.workspaceID
        device = core
        let images = core.state.favicons
        projection = BrowserSession(core: opened.session, image: { images.image(of: $0) })
        core.state.register(self, for: opened.workspaceID)
    }

    /// A workspace no one closed closes on the main queue's next turn, never
    /// inside this deinit, which may run while the core applies a batch. It
    /// is skipped once the core is gone.
    isolated deinit {
        guard isOpen, let device else { return }
        let closing = CloseWorkspace(workspaceID: workspaceID)
        DispatchQueue.main.async { [weak device] in
            MainActor.assumeIsolated { _ = try? device?.send(closing) }
        }
    }

    // MARK: - Actions - Opening

    /// Opens a workspace of `kind` in `core`. With `seed`, a session in the
    /// stored format for launches without a file (isolated runs, previews,
    /// tests), it keeps nothing: it is never saved or synced, and its tabs wear
    /// the images `seed` carries. Without one, a private workspace starts from
    /// the core's private template. Throws the rule that refuses it.
    static func open(_ kind: WorkspaceKind, seed: BrowserSession?, in core: CrestCore) throws
        -> BrowserCoreSessionAuthority
    {
        let bytes = try seed.map { try JSONEncoder().encode(compact($0)) }
        let opened = Self.opened(by: try core.send(OpenWorkspace(kind: kind, seed: bytes)))
        if let seed { core.state.adoptImages(OfferedImages(placedFrom: seed).placed, in: opened.workspaceID) }
        return BrowserCoreSessionAuthority(opened: opened, core: core)
    }

    /// Opens the session `core` keeps in its file, as it loaded and repaired
    /// it. Each tab wears the image `favicons` keeps for it, and a tab the
    /// repair gave a new identity wears its source's. Throws `NoStoredSession`
    /// while the file holds no session yet.
    static func openStored(in core: CrestCore, favicons: any BrowserFaviconStoring) throws(Rejection)
        -> BrowserCoreSessionAuthority
    {
        let changes = try core.send(OpenWorkspace(kind: .persistent, seed: nil))
        let opened = Self.opened(by: changes)
        var images: [UUID: Data] = [:]
        for space in opened.session.spaces {
            for tab in space.tabs { images[tab.id] = favicons.favicon(tabID: TabID(rawValue: tab.id)) }
        }
        for case .tabCopied(let copied) in changes where copied.workspaceID == opened.workspaceID {
            images[copied.copyTabID] = favicons.favicon(tabID: TabID(rawValue: copied.sourceTabID))
        }
        core.state.adoptImages(images, in: opened.workspaceID)
        return BrowserCoreSessionAuthority(opened: opened, core: core)
    }

    /// Opens a workspace that borrows the Space `assignment` names, with its
    /// profile, settings and access grants, and tabs of its own. It follows
    /// this workspace's edits of the Space's settings and closes once this
    /// workspace no longer lends it. Throws the rule that refuses it.
    func borrow(_ assignment: BrowserSpaceRuntimeAssignment) throws(Rejection) -> BrowserCoreSessionAuthority {
        guard let device else { preconditionFailure("A workspace lends its Space only while its core exists.") }
        let changes = try device.send(
            BorrowSpace(workspaceID: workspaceID, spaceID: assignment.spaceID.rawValue, profileID: assignment.profileID)
        )
        return BrowserCoreSessionAuthority(opened: Self.opened(by: changes), core: device)
    }

    /// The workspace an intent that opens one announced.
    private static func opened(by changes: [Change]) -> WorkspaceOpened {
        for case .workspaceOpened(let opened) in changes.reversed() { return opened }
        preconditionFailure("The core opened a workspace without announcing it. Rebuild the core.")
    }

    // MARK: - Actions - Closing

    /// Closes the workspace, and first every workspace that borrows from it:
    /// its pages and windows go and its session takes no edits. The device
    /// keeps its windows' saved records. Closing it again does nothing.
    func close() {
        guard isOpen else { return }
        _ = try? device?.send(CloseWorkspace(workspaceID: workspaceID))
        isOpen = false
    }

    // MARK: - Actions - Changes

    /// TRANSITIONAL until S6.7: one session change the core published for this
    /// workspace. See `BrowserSession.apply(_:images:)`.
    func receive(_ change: Change, images: FaviconAssets) {
        if case .workspaceClosed = change { isOpen = false }
        projection.apply(change, images: images)
    }

    /// Applies what the core published for a commit that just returned, with
    /// the images its issuer offered.
    private func follow(offering images: OfferedImages = OfferedImages()) {
        guard let device else { return }
        device.state.favicons.offer(images, in: workspaceID)
        defer { device.state.favicons.withdrawOffer(in: workspaceID) }
        device.drain()
    }

    // MARK: - Actions - Replacement

    /// Replaces the session and saves it before publishing. With a sync
    /// transaction its journal is saved and published with the session. A
    /// failed save leaves the projection and the core's session unchanged.
    func replaceDurably(with proposed: BrowserSession, sync: BrowserCoreSyncTransaction? = nil) throws {
        // The delta is measured from the copy, which must hold every change
        // the core already published.
        follow()
        let next = keepingPreferences(proposed)
        let delta = try JSONEncoder().encode(try delta(to: next))
        let app = try appHandle()
        let result = withUnsafeBytes(of: workspaceID.uuid) { workspace in
            delta.withUnsafeBytes { bytes in
                crest_session_replace_durably(
                    app, workspace.bindMemory(to: UInt8.self).baseAddress, sync?.handle ?? 0,
                    bytes.bindMemory(to: UInt8.self).baseAddress, delta.count)
            }
        }
        guard result == CREST_OK else { throw CoreError(result) }
        follow(offering: OfferedImages(placedFrom: next))
    }

    /// The core the workspace is open in, which the durable replacement names
    /// with it.
    private func appHandle() throws -> UInt64 {
        guard let device else { throw CoreError.rejected(CREST_INVALID_HANDLE) }
        return device.handle
    }

    // MARK: - Actions - Deltas

    private func delta(to next: BrowserSession) throws -> Delta {
        var result = Delta()
        var oldHeader = projection
        oldHeader.spaces = []
        var newHeader = next
        newHeader.spaces = []
        if oldHeader != newHeader { result.metadata = newHeader }
        if projection.spaces.map(\.id) != next.spaces.map(\.id) {
            result.spaceOrder = next.spaces.map(\.id.rawValue)
        }
        let oldSpaces = Dictionary(uniqueKeysWithValues: projection.spaces.map { ($0.id, $0) })
        for space in next.spaces {
            let previous = oldSpaces[space.id]
            guard previous != space else { continue }
            var change = SpaceChange(id: space.id.rawValue)
            let metadata = Self.metadata(space)
            if previous.map(Self.metadata) != metadata { change.metadata = metadata }
            change.tabs = Self.collection(
                previous?.tabs.map(Self.compactTab) ?? [], space.tabs.map(Self.compactTab), id: \.id.rawValue)
            change.folders = Self.collection(previous?.folders ?? [], space.folders, id: \.id.rawValue)
            change.history = Self.collection(previous?.history ?? [], space.history, id: \.id)
            change.archivedTabs = Self.collection(
                previous?.archivedTabs.map(Self.compactArchive) ?? [], space.archivedTabs.map(Self.compactArchive),
                id: \.id.rawValue)
            if !change.isEmpty { result.spaces.append(change) }
        }
        return result
    }

    private static func collection<T: Encodable & Equatable>(_ previous: [T], _ next: [T], id: (T) -> UUID)
        -> CollectionEdit<T>?
    {
        guard previous != next else { return nil }
        let oldIDs = previous.map(id)
        let nextIDs = next.map(id)
        // Older archives may contain repeated identities. Preserve their exact
        // order and contents until an archive operation explicitly changes them.
        guard Set(oldIDs).count == oldIDs.count, Set(nextIDs).count == nextIDs.count else {
            return .replace(next)
        }
        let old = Dictionary(uniqueKeysWithValues: zip(oldIDs, previous))
        let retained = Set(nextIDs)
        return .edit(
            remove: oldIDs.filter { !retained.contains($0) },
            upsert: next.filter { old[id($0)] != $0 },
            order: oldIDs != nextIDs ? nextIDs : nil)
    }

    private nonisolated static func compactTab(_ source: BrowserTab) -> BrowserTab {
        var tab = source
        tab.faviconData = nil
        return tab
    }

    private nonisolated static func compactArchive(_ source: ArchivedTab) -> ArchivedTab {
        var entry = source
        entry.tab.faviconData = nil
        return entry
    }

    private static func metadata(_ source: BrowserSpace) -> BrowserSpace {
        var space = source
        space.tabs = []
        space.folders = []
        space.history = []
        space.archivedTabs = []
        return space
    }

    nonisolated static func compact(_ source: BrowserSession) -> BrowserSession {
        var session = source
        for index in session.spaces.indices {
            session.spaces[index].tabs = session.spaces[index].tabs.map(compactTab)
            session.spaces[index].archivedTabs = session.spaces[index].archivedTabs.map(compactArchive)
        }
        return session
    }
}

// MARK: - App preferences

extension BrowserCoreSessionAuthority {
    /// The core keeps its preference record through value edits and sync
    /// replacement; the projection follows the same rule.
    fileprivate func keepingPreferences(_ proposed: BrowserSession) -> BrowserSession {
        var next = proposed
        next.appPreferences = projection.appPreferences
        return next
    }
}
