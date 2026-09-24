import CrestCoreABI
import Foundation
import Observation

/// One core session per store family, attached to the core's device from the
/// moment it exists. `projection` is the Swift copy of the session the core
/// holds, with native favicon assets; only the session changes the core
/// publishes update it (see `BrowserCoreSessionBridge.swift`), so it can never
/// show an unaccepted edit. It holds browsing data only. What each window shows
/// is the core device's: a command names the window that issued it, and the
/// device moves that window when the command commits and repairs the others.
/// A command commits only while the core still holds the session it was
/// prepared against; nothing here names a revision.
@Observable @MainActor
final class BrowserCoreSessionAuthority {
    // MARK: - Types

    /// What kind of workspace a session holds. Raw values are the core's
    /// `coreWorkspaceKind` spellings.
    enum WorkspaceKind: String, Encodable, Sendable {
        case persistent
        case `private`
    }

    final class PreparedTransfer {
        fileprivate let handle: UInt64

        fileprivate init(handle: UInt64) {
            self.handle = handle
        }

        deinit { crest_session_release_transfer(handle) }
    }

    final class PreparedChange {
        fileprivate let handle: UInt64
        /// TRANSITIONAL until S6.7: the session the command proposes. A tab
        /// batch previews it, and an import's commit offers the images it gives
        /// the tabs it brings in; every other tab it places already has its
        /// image in `FaviconAssets`.
        let session: BrowserSession

        fileprivate init(handle: UInt64, session: BrowserSession) {
            self.handle = handle
            self.session = session
        }

        deinit { crest_session_release_command(handle) }
    }

    /// The images the issuer of a command holds, which `FaviconAssets` places
    /// while the core's changes for the command are applied.
    typealias OfferedImages = FaviconAssets.Offer

    /// The session a new core session starts from, with its workspace kind
    /// beside the session's own members.
    private struct Creation: Encodable {
        private enum CodingKeys: String, CodingKey {
            case coreWorkspaceKind
            case corePrivateBrowsing
        }

        let session: BrowserSession
        let workspaceKind: WorkspaceKind
        let privateBrowsing: Bool

        func encode(to encoder: any Encoder) throws {
            try session.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(workspaceKind, forKey: .coreWorkspaceKind)
            try container.encode(privateBrowsing, forKey: .corePrivateBrowsing)
        }
    }

    /// The Space a borrowed session borrows.
    private struct Borrowing: Encodable {
        let spaceId: UUID
        let profileId: UUID
    }

    /// One session command: its operation, the Space it runs in (null for a
    /// command without one), its arguments and the window that issued it
    /// (null for none).
    private struct Command<Arguments: Encodable>: Encodable {
        let version = 1
        let operation: BrowserSessionOperation
        @BrowserCoreNullable var spaceId: UUID?
        @BrowserCoreNullable var profileId: UUID?
        let arguments: Arguments
        @BrowserCoreNullable var windowId: UUID?
        let now: TimeInterval
    }

    /// `tab.transfer` between two Spaces of this workspace.
    private struct TabTransferCommand: Encodable {
        let version = 1
        let operation = BrowserSessionOperation.tabTransfer
        let spaceId: UUID
        let profileId: UUID
        let destinationSpaceId: UUID
        let destinationProfileId: UUID
        let arguments: BrowserCoreTabTransfer.Arguments
        @BrowserCoreNullable var windowId: UUID?
        let now: TimeInterval
    }

    /// A tab moving between two workspaces, from the window it leaves to the
    /// one it moves to.
    private struct WorkspaceTransfer: Encodable {
        let version = 1
        let spaceId: UUID
        let profileId: UUID
        @BrowserCoreNullable var sourceWindowId: UUID?
        @BrowserCoreNullable var destinationWindowId: UUID?
        let arguments: BrowserCoreTabTransfer.Arguments
        let now: TimeInterval
    }

    /// `workspace.import`.
    private struct WorkspaceImportCommand: Encodable {
        let version = 1
        let operation = BrowserSessionOperation.workspaceImport
        let mode: BrowserCoreWorkspaceImport.Mode
        let arguments: BrowserCoreWorkspaceImport.Arguments
        @BrowserCoreNullable var windowId: UUID?
        let now: TimeInterval
    }

    /// A record command's answer, read only for whether it changed anything.
    private struct RecordAnswer: Decodable {
        struct Change: Decodable {}

        let changes: [Change]
    }

    /// The edits that take the accepted records to a proposed session.
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

    private final class SessionHandle: Sendable {
        let value: UInt64
        init(value: UInt64) { self.value = value }
        deinit { crest_session_destroy(value) }
    }

    // MARK: - Variables

    private(set) var projection: BrowserSession
    @ObservationIgnored private let owner: SessionHandle
    @ObservationIgnored private let borrowedSource: BrowserCoreSessionAuthority?
    /// The core whose device shows this session in its windows, and the
    /// workspace it gave the session.
    @ObservationIgnored private(set) weak var device: CrestCore?
    @ObservationIgnored private(set) var workspaceID: UUID?

    // MARK: - Initializers

    /// A memory-only session over `session`, attached to `core`'s device.
    init(
        session: BrowserSession, workspaceKind: WorkspaceKind = .persistent, privateBrowsing: Bool = false,
        core: CrestCore
    ) {
        projection = session
        borrowedSource = nil
        do {
            let data = try JSONEncoder().encode(
                Creation(
                    session: Self.compact(session), workspaceKind: workspaceKind,
                    privateBrowsing: privateBrowsing || workspaceKind == .private))
            var handle: UInt64 = 0
            let result = data.withUnsafeBytes {
                crest_session_create($0.bindMemory(to: UInt8.self).baseAddress, data.count, &handle)
            }
            guard result == CREST_OK else { throw CoreError.rejected(result) }
            owner = SessionHandle(value: handle)
        } catch {
            preconditionFailure("Could not initialize the core session: \(error)")
        }
        attach(to: core)
    }

    /// TRANSITIONAL until session intents land: the persistent session `core`
    /// keeps in its file, taken over with the projection it loaded.
    init(adopting handle: UInt64, projection: BrowserSession, core: CrestCore) {
        owner = SessionHandle(value: handle)
        self.projection = projection
        borrowedSource = nil
        attach(to: core)
    }

    private init(owner: SessionHandle, borrowedSource: BrowserCoreSessionAuthority, core: CrestCore) {
        self.owner = owner
        projection = BrowserSession(spaces: [])
        self.borrowedSource = borrowedSource
        attach(to: core)
    }

    // MARK: - Actions - Device

    /// Attaches this session to `core`'s device so its windows may show it.
    /// The device publishes the session whole, which the projection takes,
    /// wearing the images the session it starts from wears. The persistent
    /// session is attached when the core loads its file, and may have been
    /// published already, so its tabs take those images first.
    private func attach(to core: CrestCore) {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = crest_session_attach_device(owner.value, core.handle, &bytes)
        guard status == CREST_OK else { CrestCore.buildBug(status, "attach a session to its device") }
        let workspace = bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
        device = core
        workspaceID = workspace
        core.state.register(self, for: workspace)
        let images = OfferedImages(placedFrom: projection)
        core.state.adoptImages(images.placed, in: workspace)
        follow(offering: images)
    }

    /// TRANSITIONAL until S6.7: one session change the core published for this
    /// workspace. See `BrowserSession.apply(_:images:)`.
    func receive(_ change: Change, images: FaviconAssets) {
        projection.apply(change, images: images)
    }

    /// Applies what the core published for a commit that just returned, with
    /// the images its issuer offered.
    private func follow(offering images: OfferedImages = OfferedImages()) {
        guard let device, let workspaceID else { return }
        device.state.favicons.offer(images, in: workspaceID)
        defer { device.state.favicons.withdrawOffer(in: workspaceID) }
        device.drain()
    }

    // MARK: - Actions - Borrowing

    func makeBorrowed(in assignment: BrowserSpaceRuntimeAssignment) throws -> BrowserCoreSessionAuthority {
        guard let device else { preconditionFailure("A session borrows only once it shows in a core's windows.") }
        let input = try JSONEncoder().encode(
            Borrowing(spaceId: assignment.spaceID.rawValue, profileId: assignment.profileID))
        var handle: UInt64 = 0
        let status = input.withUnsafeBytes {
            crest_session_create_borrowed(owner.value, $0.bindMemory(to: UInt8.self).baseAddress, input.count, &handle)
        }
        guard status == CREST_OK else { throw CoreError.rejected(status) }
        return BrowserCoreSessionAuthority(owner: SessionHandle(value: handle), borrowedSource: self, core: device)
    }

    /// Only the source authority supplies policy. Native callers cannot substitute
    /// a session snapshot or turn local organization into canonical profile edits.
    /// Answers whether the borrowed Space changed.
    @discardableResult
    func refreshBorrowed() throws -> Bool {
        guard borrowedSource != nil else { return false }
        let previous = projection
        var command: UInt64 = 0
        let prepared = crest_session_prepare_borrowed_refresh(owner.value, &command)
        guard prepared == CREST_OK else { throw CoreError.rejected(prepared) }
        defer { crest_session_release_command(command) }
        let committed = crest_session_commit_command(command)
        guard committed == CREST_OK else { throw CoreError.rejected(committed) }
        follow()
        return projection != previous
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
        let result = delta.withUnsafeBytes { bytes in
            crest_session_replace_durably(
                owner.value, sync?.handle ?? 0, bytes.bindMemory(to: UInt8.self).baseAddress, delta.count)
        }
        guard result == CREST_OK else { throw CoreError(result) }
        follow(offering: OfferedImages(placedFrom: next))
    }

    func attachSync(_ sync: BrowserCoreSyncAuthority) throws {
        let result = crest_session_attach_sync(owner.value, sync.handle)
        guard result == CREST_OK else { throw CoreError.rejected(result) }
    }

    /// Gates commands on Space access grants. Native controllers keep their own
    /// checks; this makes the records refuse a locked Space even so.
    func attachAccess(_ access: BrowserCoreSpaceAccess) throws {
        let result = crest_session_attach_access(owner.value, access.handle)
        guard result == CREST_OK else { throw CoreError.rejected(result) }
    }

    // MARK: - Actions - Transfers

    func prepareTabMove(
        _ tabID: TabID, source: BrowserSpaceRuntimeAssignment,
        destination: BrowserSpaceRuntimeAssignment, arguments: BrowserCoreTabTransfer.Arguments,
        window: UUID?, at date: Date
    ) throws -> PreparedChange {
        guard let moved = projection.space(id: source.spaceID)?.tabs.first(where: { $0.id == tabID })
        else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
        let data = try JSONEncoder().encode(
            TabTransferCommand(
                spaceId: source.spaceID.rawValue, profileId: source.profileID,
                destinationSpaceId: destination.spaceID.rawValue, destinationProfileId: destination.profileID,
                arguments: arguments, windowId: window, now: date.timeIntervalSinceReferenceDate))
        let handle = try prepareCommand(data)
        do {
            let result = try JSONDecoder().decode(BrowserCoreTabTransfer.Result.self, from: readCommand(handle))
            let intermediate = try BrowserCoreTabTransfer.applying(result.source, to: projection, moved: moved)
            let next = try BrowserCoreTabTransfer.applying(result.destination, to: intermediate, moved: moved)
            return PreparedChange(handle: handle, session: next)
        } catch {
            crest_session_release_command(handle)
            throw error
        }
    }

    /// Whether the core would accept a cross-Space move. The command is
    /// prepared, read and released without committing.
    func acceptsTabMove(
        _ tabID: TabID, source: BrowserSpaceRuntimeAssignment,
        destination: BrowserSpaceRuntimeAssignment, window: UUID?
    ) -> Bool {
        (try? prepareTabMove(
            tabID, source: source, destination: destination,
            arguments: BrowserCoreTabTransfer.Arguments(tabID: tabID), window: window, at: .now)) != nil
    }

    static func prepareTransfer(
        source: BrowserCoreSessionAuthority, sourceWindow: UUID?,
        destination: BrowserCoreSessionAuthority, destinationWindow: UUID?,
        tabID: TabID, assignment: BrowserSpaceRuntimeAssignment, selecting: Bool
    ) throws -> PreparedTransfer {
        guard source.projection.space(id: assignment.spaceID)?.contains(tabID) == true
        else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
        let input = try JSONEncoder().encode(
            WorkspaceTransfer(
                spaceId: assignment.spaceID.rawValue, profileId: assignment.profileID,
                sourceWindowId: sourceWindow, destinationWindowId: destinationWindow,
                arguments: BrowserCoreTabTransfer.Arguments(tabID: tabID, selecting: selecting),
                now: Date.now.timeIntervalSinceReferenceDate))
        var handle: UInt64 = 0
        let status = input.withUnsafeBytes { bytes in
            crest_session_prepare_transfer(
                source.owner.value, destination.owner.value, bytes.bindMemory(to: UInt8.self).baseAddress,
                input.count, &handle)
        }
        guard status == CREST_OK else { throw CoreError.rejected(status) }
        return PreparedTransfer(handle: handle)
    }

    /// Commits a prepared transfer: the core stages the side that syncs and
    /// saves the side that keeps a file, with that journal, before either side
    /// is published. Both sides arrive in one batch, so the moved tab keeps
    /// the image it wore in the workspace it left.
    static func commitTransfer(
        _ prepared: PreparedTransfer,
        source: BrowserCoreSessionAuthority, destination: BrowserCoreSessionAuthority
    ) throws {
        let committed = crest_session_commit_transfer(prepared.handle)
        guard committed == CREST_OK else { throw CoreError(committed) }
        destination.follow()
    }

    // MARK: - Actions - Commands

    /// Whether the core would accept a tab, folder or split command: it is
    /// prepared against the owned records and released without committing.
    /// This is how native menus ask the core's rules (folder depth, split
    /// capacity) instead of keeping copies of them.
    func accepts<Arguments: Encodable>(
        _ operation: BrowserSessionOperation, in spaceID: SpaceID, arguments: Arguments,
        window: UUID?
    ) -> Bool {
        guard let space = projection.space(id: spaceID),
            let data = try? JSONEncoder().encode(
                Command(
                    operation: operation, spaceId: spaceID.rawValue, profileId: space.profile.id,
                    arguments: arguments, windowId: window,
                    now: Date.now.timeIntervalSinceReferenceDate)),
            let handle = try? prepareCommand(data)
        else { return false }
        crest_session_release_command(handle)
        return true
    }

    /// Runs a tab, folder or split command. `image` is the image a page
    /// reported, which the tab the core assigns it to wears.
    func execute<Arguments: Encodable>(
        _ operation: BrowserSessionOperation, in spaceID: SpaceID, arguments: Arguments,
        window: UUID?, at date: Date, image: Data? = nil
    ) throws -> BrowserCoreSessionEditing.Result {
        guard let space = projection.space(id: spaceID) else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
        let data = try JSONEncoder().encode(
            Command(
                operation: operation, spaceId: spaceID.rawValue, profileId: space.profile.id,
                arguments: arguments, windowId: window, now: date.timeIntervalSinceReferenceDate))
        return try commitCommand(data, offering: OfferedImages(assigned: image)) {
            try JSONDecoder().decode(BrowserCoreSessionEditing.Result.self, from: $0)
        }
    }

    func executeSpace<Arguments: Encodable>(
        _ operation: BrowserSessionOperation, in spaceID: SpaceID?, arguments: Arguments,
        window: UUID?, at date: Date
    ) throws {
        let space = spaceID.flatMap { projection.space(id: $0) }
        let data = try JSONEncoder().encode(
            Command(
                operation: operation, spaceId: spaceID?.rawValue, profileId: space?.profile.id,
                arguments: arguments, windowId: window, now: date.timeIntervalSinceReferenceDate))
        try commitCommand(data) { _ in }
    }

    /// Runs a history, archive, retention or split metadata command, and
    /// answers whether it changed anything.
    func executeRecords<Arguments: Encodable>(
        _ operation: BrowserSessionOperation, in spaceID: SpaceID?, arguments: Arguments,
        window: UUID?, at date: Date
    ) throws -> Bool {
        let space = spaceID.flatMap { projection.space(id: $0) }
        let data = try JSONEncoder().encode(
            Command(
                operation: operation, spaceId: spaceID?.rawValue, profileId: space?.profile.id,
                arguments: arguments, windowId: window, now: date.timeIntervalSinceReferenceDate))
        return try commitCommand(data) { !(try JSONDecoder().decode(RecordAnswer.self, from: $0).changes.isEmpty) }
    }

    func prepareTabBatch(
        _ request: BrowserTabBatchRequest, arguments: BrowserCoreTabBatch.Arguments, window: UUID?,
        at date: Date
    ) throws -> (command: PreparedChange, result: BrowserTabBatchResult) {
        let data = try JSONEncoder().encode(
            Command(
                operation: .tabsBatch, spaceId: request.assignment.spaceID.rawValue,
                profileId: request.assignment.profileID, arguments: arguments, windowId: window,
                now: date.timeIntervalSinceReferenceDate))
        let handle = try prepareCommand(data)
        do {
            let response = try JSONDecoder().decode(BrowserCoreTabBatch.Response.self, from: readCommand(handle))
            let prepared = try BrowserCoreTabBatch.applying(response, to: projection)
            return (
                PreparedChange(handle: handle, session: prepared.session),
                prepared.result
            )
        } catch {
            crest_session_release_command(handle)
            throw error
        }
    }

    func prepareWorkspace(_ request: BrowserCoreWorkspaceImport.Request, window: UUID?) throws -> PreparedChange {
        let input = try JSONEncoder().encode(
            WorkspaceImportCommand(
                mode: request.mode, arguments: request.arguments, windowId: window,
                now: Date.now.timeIntervalSinceReferenceDate))
        let handle = try prepareCommand(input)
        do {
            let result = try JSONDecoder().decode(BrowserCoreWorkspaceImport.Result.self, from: readCommand(handle))
            let next = try result.materialize(existing: projection, request: request)
            return PreparedChange(handle: handle, session: next)
        } catch {
            crest_session_release_command(handle)
            throw error
        }
    }

    /// Commits a prepared command. The core saves one whose effects outside it
    /// depend on the file, with the journal it stages, before this returns; a
    /// failed save or stage leaves the projection and the core's session
    /// unchanged. The tabs it places wear the images the prepared session gave
    /// them.
    func commit(_ command: PreparedChange) throws {
        let result = crest_session_commit_command(command.handle)
        guard result == CREST_OK else { throw CoreError(result) }
        follow(offering: OfferedImages(placedFrom: command.session))
    }

    // MARK: - Actions - Core calls

    /// Prepares, reads and commits one command, then applies what the core
    /// published for it. The answer is read before the commit, so a failed
    /// read commits nothing.
    @discardableResult
    private func commitCommand<Result>(
        _ data: Data, offering images: OfferedImages = OfferedImages(), decode: (Data) throws -> Result
    ) throws -> Result {
        let command = try prepareCommand(data)
        defer { crest_session_release_command(command) }
        let result = try decode(try readCommand(command))
        let committed = crest_session_commit_command(command)
        guard committed == CREST_OK else { throw CoreError(committed) }
        follow(offering: images)
        return result
    }

    private func prepareCommand(_ data: Data) throws -> UInt64 {
        var command: UInt64 = 0
        let prepared = data.withUnsafeBytes {
            crest_session_prepare_command(owner.value, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &command)
        }
        guard prepared == CREST_OK else { throw CoreError.rejected(prepared) }
        return command
    }

    private func readCommand(_ command: UInt64) throws -> Data {
        var length = 0
        let measured = crest_session_read_command(command, nil, 0, &length)
        guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= 64 * 1024 * 1024 else {
            throw CoreError.rejected(measured)
        }
        let capacity = length
        var output = Data(count: capacity)
        let read = output.withUnsafeMutableBytes {
            crest_session_read_command(command, $0.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
        }
        guard read == CREST_OK else { throw CoreError.rejected(read) }
        return output
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
    /// Applies one `preferences.*` command, and answers whether the
    /// preferences changed. Only the preference record changes, so every
    /// window and Space record stays exactly as it was.
    func executePreferences(_ request: BrowserAppPreferenceRequest) throws -> Bool {
        let before = projection.appPreferences
        try commitCommand(try JSONEncoder().encode(request)) { _ in }
        return projection.appPreferences != before
    }

    /// The core keeps its preference record through value edits and sync
    /// replacement; the projection follows the same rule.
    fileprivate func keepingPreferences(_ proposed: BrowserSession) -> BrowserSession {
        var next = proposed
        next.appPreferences = projection.appPreferences
        return next
    }

    /// Reads a core answer that changes nothing: the command is prepared, read
    /// and released without committing.
    func read<Request: Encodable>(_ request: Request) throws -> Data {
        let command = try prepareCommand(try JSONEncoder().encode(request))
        defer { crest_session_release_command(command) }
        return try readCommand(command)
    }
}
