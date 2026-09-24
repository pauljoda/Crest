import CrestCoreABI
import Foundation
import Observation

/// One core session per store family. `projection` is the accepted native read
/// model, including native favicon assets; it cannot publish an unaccepted edit.
/// It holds browsing data only: each command reads what the requesting window
/// shows as context (`view`) and answers with a `BrowserSelectionHint` the window
/// applies to its own selection.
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
        let source: BrowserSession
        let destination: BrowserSession
        let sourceHint: BrowserSelectionHint
        let destinationHint: BrowserSelectionHint

        fileprivate init(
            handle: UInt64, source: BrowserSession, destination: BrowserSession,
            sourceHint: BrowserSelectionHint, destinationHint: BrowserSelectionHint
        ) {
            self.handle = handle
            self.source = source
            self.destination = destination
            self.sourceHint = sourceHint
            self.destinationHint = destinationHint
        }

        deinit { crest_session_release_transfer(handle) }
    }

    final class PreparedChange {
        fileprivate let handle: UInt64
        let session: BrowserSession
        /// The follow-up selection for the window that issued the command.
        let hint: BrowserSelectionHint

        fileprivate init(handle: UInt64, session: BrowserSession, hint: BrowserSelectionHint) {
            self.handle = handle
            self.session = session
            self.hint = hint
        }

        deinit { crest_session_release_command(handle) }
    }

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

    /// What a window shows, as read-only command context: its Space and the tab
    /// it shows in each of the session's Spaces (null for none).
    private struct View: Encodable {
        struct Tab: Encodable {
            let spaceId: UUID
            @BrowserCoreNullable var tabId: UUID?
        }

        let spaceId: UUID
        let tabs: [Tab]

        init(_ selection: BrowserStoreSelection, in session: BrowserSession) {
            spaceId = selection.selectedSpaceID.rawValue
            tabs = session.spaces.map { space in
                Tab(spaceId: space.id.rawValue, tabId: selection.selectedTabID(in: space.id)?.rawValue)
            }
        }
    }

    /// One session command: its operation, the Space it runs in (null for a
    /// command without one), its arguments and the issuing window's view.
    private struct Command<Arguments: Encodable>: Encodable {
        let version = 1
        let operation: BrowserSessionOperation
        @BrowserCoreNullable var spaceId: UUID?
        @BrowserCoreNullable var profileId: UUID?
        let arguments: Arguments
        let view: View
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
        let view: View
        let now: TimeInterval
    }

    /// A tab moving between two workspaces, with each side's view.
    private struct WorkspaceTransfer: Encodable {
        let version = 1
        let spaceId: UUID
        let profileId: UUID
        let sourceView: View
        let destinationView: View
        let arguments: BrowserCoreTabTransfer.Arguments
        let now: TimeInterval
    }

    /// `workspace.import`.
    private struct WorkspaceImportCommand: Encodable {
        let version = 1
        let operation = BrowserSessionOperation.workspaceImport
        let mode: BrowserCoreWorkspaceImport.Mode
        let arguments: BrowserCoreWorkspaceImport.Arguments
        let view: View
        let now: TimeInterval
    }

    private struct BorrowedCreation: Decodable {
        let session: BrowserSession
    }

    private struct MetadataProjection: Decodable {
        var session: BrowserSession
        let selection: BrowserSelectionHint?
    }

    private struct RecordChanges: Decodable {
        struct Change: Decodable {
            let spaceId: UUID
            let profileId: UUID
            let historyEntry: BrowserHistoryEntry?
            let removedHistory: [UUID]?
            let removedArchiveIndices: [Int]?
            let tabEdit: BrowserCoreSessionEditing.Result?
            let splitGroups: [BrowserSplitGroupMetadata]?
        }

        let changes: [Change]
        let selection: BrowserSelectionHint?
    }

    private struct PreferencesResult: Decodable {
        let preferences: BrowserAppPreferences
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
    @ObservationIgnored private var revision: UInt64
    @ObservationIgnored private let owner: SessionHandle
    @ObservationIgnored private var borrowedSource: BrowserCoreSessionAuthority?
    @ObservationIgnored private var borrowedSourceRevision: UInt64?

    /// The core's revision of this session, for waiting until it is on disk.
    var acceptedRevision: UInt64 { revision }

    // MARK: - Initializers

    init(session: BrowserSession, workspaceKind: WorkspaceKind = .persistent, privateBrowsing: Bool = false) {
        projection = session
        do {
            let data = try JSONEncoder().encode(
                Creation(
                    session: Self.compact(session), workspaceKind: workspaceKind,
                    privateBrowsing: privateBrowsing || workspaceKind == .private))
            var handle: UInt64 = 0
            var initialRevision: UInt64 = 0
            let result = data.withUnsafeBytes {
                crest_session_create($0.bindMemory(to: UInt8.self).baseAddress, data.count, &handle, &initialRevision)
            }
            guard result == CREST_OK else { throw CoreError.rejected(result) }
            let sessionOwner = SessionHandle(value: handle)
            let descriptor = try BrowserEngineRegistration.current.encoded()
            let registered = descriptor.withUnsafeBytes {
                crest_session_register_engine(handle, $0.bindMemory(to: UInt8.self).baseAddress, descriptor.count)
            }
            guard registered == CREST_OK else { throw CoreError.rejected(registered) }
            owner = sessionOwner
            revision = initialRevision
        } catch {
            preconditionFailure("Could not initialize the core session: \(error)")
        }
    }

    /// TRANSITIONAL until session intents land: the persistent session the
    /// core keeps in its file, taken over with the projection it loaded.
    init(adopting handle: UInt64, revision: UInt64, projection: BrowserSession) {
        owner = SessionHandle(value: handle)
        self.revision = revision
        self.projection = projection
        do {
            let descriptor = try BrowserEngineRegistration.current.encoded()
            let registered = descriptor.withUnsafeBytes {
                crest_session_register_engine(handle, $0.bindMemory(to: UInt8.self).baseAddress, descriptor.count)
            }
            guard registered == CREST_OK else { throw CoreError.rejected(registered) }
        } catch {
            preconditionFailure("Could not register the engine with the stored session: \(error)")
        }
    }

    private init(
        owner: SessionHandle, revision: UInt64, projection: BrowserSession,
        borrowedSource: BrowserCoreSessionAuthority
    ) {
        self.owner = owner
        self.revision = revision
        self.projection = projection
        self.borrowedSource = borrowedSource
        borrowedSourceRevision = borrowedSource.revision
    }

    // MARK: - Actions - Borrowing

    func makeBorrowed(in assignment: BrowserSpaceRuntimeAssignment) throws -> BrowserCoreSessionAuthority {
        let input = try JSONEncoder().encode(
            Borrowing(spaceId: assignment.spaceID.rawValue, profileId: assignment.profileID))
        var handle: UInt64 = 0
        var initialRevision: UInt64 = 0
        var command: UInt64 = 0
        let status = input.withUnsafeBytes {
            crest_session_create_borrowed(
                owner.value, revision, $0.bindMemory(to: UInt8.self).baseAddress,
                input.count, &handle, &initialRevision, &command)
        }
        guard status == CREST_OK else { throw CoreError.rejected(status) }
        let child = SessionHandle(value: handle)
        defer { crest_session_release_command(command) }
        let session = try JSONDecoder().decode(BorrowedCreation.self, from: readCommand(command)).session
        return BrowserCoreSessionAuthority(
            owner: child, revision: initialRevision, projection: session, borrowedSource: self)
    }

    /// Only the source authority supplies policy. Native callers cannot substitute
    /// a session snapshot or turn local organization into canonical profile edits.
    @discardableResult
    func refreshBorrowed() throws -> Bool {
        guard let borrowedSource, borrowedSourceRevision != borrowedSource.revision else { return false }
        var command: UInt64 = 0
        let prepared = crest_session_prepare_borrowed_refresh(owner.value, revision, &command)
        guard prepared == CREST_OK else { throw CoreError.rejected(prepared) }
        defer { crest_session_release_command(command) }
        let next = try decodeMetadataProjection(readCommand(command)).session
        var accepted: UInt64 = 0
        let committed = crest_session_commit_command(command, &accepted)
        guard committed == CREST_OK else { throw CoreError.rejected(committed) }
        revision = accepted
        borrowedSourceRevision = borrowedSource.revision
        let changed = projection != next
        projection = next
        return changed
    }

    // MARK: - Actions - Replacement

    /// Replaces the session and saves it before publishing. With a sync
    /// transaction its journal is saved and published with the session. A
    /// failed save leaves the projection and the accepted revision unchanged.
    func replaceDurably(with proposed: BrowserSession, sync: BrowserCoreSyncTransaction? = nil) throws {
        let next = keepingPreferences(proposed)
        let delta = try JSONEncoder().encode(try delta(to: next))
        var accepted: UInt64 = 0
        let result = delta.withUnsafeBytes { bytes in
            crest_session_replace_durably(
                owner.value, revision, sync?.handle ?? 0,
                bytes.bindMemory(to: UInt8.self).baseAddress, delta.count, &accepted)
        }
        guard result == CREST_OK else { throw CoreError(result) }
        revision = accepted
        projection = next
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
        view: BrowserStoreSelection, at date: Date
    ) throws -> PreparedChange {
        guard let moved = projection.space(id: source.spaceID)?.tabs.first(where: { $0.id == tabID })
        else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
        let data = try JSONEncoder().encode(
            TabTransferCommand(
                spaceId: source.spaceID.rawValue, profileId: source.profileID,
                destinationSpaceId: destination.spaceID.rawValue, destinationProfileId: destination.profileID,
                arguments: arguments, view: View(view, in: projection), now: date.timeIntervalSinceReferenceDate))
        let handle = try prepareCommand(data)
        do {
            let result = try JSONDecoder().decode(BrowserCoreTabTransfer.Result.self, from: readCommand(handle))
            let intermediate = try BrowserCoreTabTransfer.applying(result.source, to: projection, moved: moved)
            let next = try BrowserCoreTabTransfer.applying(result.destination, to: intermediate, moved: moved)
            return PreparedChange(handle: handle, session: next, hint: result.selection ?? .none)
        } catch {
            crest_session_release_command(handle)
            throw error
        }
    }

    /// Whether the core would accept a cross-Space move. The command is
    /// prepared, read and released without committing.
    func acceptsTabMove(
        _ tabID: TabID, source: BrowserSpaceRuntimeAssignment,
        destination: BrowserSpaceRuntimeAssignment, view: BrowserStoreSelection
    ) -> Bool {
        (try? prepareTabMove(
            tabID, source: source, destination: destination,
            arguments: BrowserCoreTabTransfer.Arguments(tabID: tabID), view: view, at: .now)) != nil
    }

    static func prepareTransfer(
        source: BrowserCoreSessionAuthority, sourceView: BrowserStoreSelection,
        destination: BrowserCoreSessionAuthority, destinationView: BrowserStoreSelection,
        tabID: TabID, assignment: BrowserSpaceRuntimeAssignment, fallback: TabID?, selecting: Bool
    ) throws -> PreparedTransfer {
        guard let moved = source.projection.space(id: assignment.spaceID)?.tabs.first(where: { $0.id == tabID })
        else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
        let input = try JSONEncoder().encode(
            WorkspaceTransfer(
                spaceId: assignment.spaceID.rawValue, profileId: assignment.profileID,
                sourceView: View(sourceView, in: source.projection),
                destinationView: View(destinationView, in: destination.projection),
                arguments: BrowserCoreTabTransfer.Arguments(tabID: tabID, fallback: fallback, selecting: selecting),
                now: Date.now.timeIntervalSinceReferenceDate))
        var handle: UInt64 = 0
        let status = input.withUnsafeBytes { bytes in
            crest_session_prepare_transfer(
                source.owner.value, source.revision, destination.owner.value, destination.revision,
                bytes.bindMemory(to: UInt8.self).baseAddress, input.count, &handle)
        }
        guard status == CREST_OK else { throw CoreError.rejected(status) }
        do {
            var length = 0
            let measured = crest_session_read_transfer(handle, nil, 0, &length)
            guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= 4 * 1024 * 1024
            else { throw CoreError.rejected(measured) }
            let capacity = length
            var data = Data(count: capacity)
            let read = data.withUnsafeMutableBytes {
                crest_session_read_transfer(handle, $0.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
            }
            guard read == CREST_OK else { throw CoreError.rejected(read) }
            let result = try JSONDecoder().decode(BrowserCoreTabTransfer.Result.self, from: data)
            return PreparedTransfer(
                handle: handle,
                source: try BrowserCoreTabTransfer.applying(result.source, to: source.projection, moved: moved),
                destination: try BrowserCoreTabTransfer.applying(
                    result.destination, to: destination.projection, moved: moved),
                sourceHint: result.sourceSelection ?? .none, destinationHint: result.destinationSelection ?? .none)
        } catch {
            crest_session_release_transfer(handle)
            throw error
        }
    }

    /// Commits a prepared transfer: the core saves the side that keeps a file,
    /// with the sync journal, before either side is published.
    static func commitTransfer(
        _ prepared: PreparedTransfer,
        source: BrowserCoreSessionAuthority, destination: BrowserCoreSessionAuthority,
        sync: BrowserCoreSyncTransaction? = nil
    ) throws {
        var sourceRevision: UInt64 = 0
        var destinationRevision: UInt64 = 0
        let committed = crest_session_commit_transfer(
            prepared.handle, sync?.handle ?? 0, &sourceRevision, &destinationRevision)
        guard committed == CREST_OK else { throw CoreError(committed) }
        source.revision = sourceRevision
        destination.revision = destinationRevision
        source.projection = prepared.source
        destination.projection = prepared.destination
    }

    // MARK: - Actions - Commands

    /// Whether the core would accept a tab, folder or split command: it is
    /// prepared against the owned records and released without committing.
    /// This is how native menus ask the core's rules (folder depth, split
    /// capacity) instead of keeping copies of them.
    func accepts<Arguments: Encodable>(
        _ operation: BrowserSessionOperation, in spaceID: SpaceID, arguments: Arguments,
        view: BrowserStoreSelection
    ) -> Bool {
        guard let space = projection.space(id: spaceID),
            let data = try? JSONEncoder().encode(
                Command(
                    operation: operation, spaceId: spaceID.rawValue, profileId: space.profile.id,
                    arguments: arguments, view: View(view, in: projection),
                    now: Date.now.timeIntervalSinceReferenceDate)),
            let handle = try? prepareCommand(data)
        else { return false }
        crest_session_release_command(handle)
        return true
    }

    func execute<Arguments: Encodable>(
        _ operation: BrowserSessionOperation, in spaceID: SpaceID, arguments: Arguments,
        view: BrowserStoreSelection, at date: Date
    ) throws -> BrowserCoreSessionEditing.Result {
        guard let index = projection.spaces.firstIndex(where: { $0.id == spaceID }) else {
            throw CoreError.rejected(CREST_INVALID_ARGUMENT)
        }
        let data = try JSONEncoder().encode(
            Command(
                operation: operation, spaceId: spaceID.rawValue, profileId: projection.spaces[index].profile.id,
                arguments: arguments, view: View(view, in: projection), now: date.timeIntervalSinceReferenceDate))
        return try commitCommand(data) { output in
            let result = try BrowserCoreSessionEditing.decode(
                output, preservingAssetsFrom: self.projection.spaces[index])
            var next = self.projection
            BrowserCoreSessionEditing.apply(result, to: &next, at: index)
            return (next, result)
        }
    }

    /// Image bytes are native assets. The command above owns their assignment;
    /// only its accepted tab identity can receive the bytes here.
    func applyFavicon(
        _ assignment: BrowserCoreSessionEditing.Result.FaviconAssignment?,
        bytes: Data?, in spaceID: SpaceID
    ) -> TabID? {
        guard let index = projection.spaces.firstIndex(where: { $0.id == spaceID }) else { return nil }
        return BrowserCoreSessionEditing.applyFavicon(assignment, bytes: bytes, to: &projection, at: index)
    }

    func executeSpace<Arguments: Encodable>(
        _ operation: BrowserSessionOperation, in spaceID: SpaceID?, arguments: Arguments,
        view: BrowserStoreSelection, at date: Date
    ) throws -> (changed: Bool, hint: BrowserSelectionHint) {
        let previous = projection
        let prepared = try prepareSpace(operation, in: spaceID, arguments: arguments, view: view, at: date)
        var accepted: UInt64 = 0
        let result = crest_session_commit_command(prepared.handle, &accepted)
        guard result == CREST_OK else { throw CoreError.rejected(result) }
        revision = accepted
        projection = prepared.session
        return (projection != previous || !prepared.hint.isEmpty, prepared.hint)
    }

    func executeRecords<Arguments: Encodable>(
        _ operation: BrowserSessionOperation, in spaceID: SpaceID?, arguments: Arguments,
        view: BrowserStoreSelection, at date: Date
    ) throws -> (changed: Bool, hint: BrowserSelectionHint) {
        let space = spaceID.flatMap { projection.space(id: $0) }
        let data = try JSONEncoder().encode(
            Command(
                operation: operation, spaceId: spaceID?.rawValue, profileId: space?.profile.id,
                arguments: arguments, view: View(view, in: projection), now: date.timeIntervalSinceReferenceDate))
        return try commitCommand(data) { output in
            let result = try JSONDecoder().decode(RecordChanges.self, from: output)
            var next = self.projection
            for change in result.changes {
                guard let index = next.spaces.firstIndex(where: { $0.id.rawValue == change.spaceId }),
                    next.spaces[index].profile.id == change.profileId
                else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
                let original = next.spaces[index]
                if var edit = change.tabEdit {
                    guard edit.space.id == original.id, edit.space.profile == original.profile else {
                        throw CoreError.rejected(CREST_INVALID_ARGUMENT)
                    }
                    var images = Dictionary(
                        original.archivedTabs.map { ($0.id, $0.tab.faviconData) },
                        uniquingKeysWith: { first, _ in first })
                    for tab in original.tabs { images[tab.id] = tab.faviconData }
                    for tabIndex in edit.space.tabs.indices {
                        edit.space.tabs[tabIndex].faviconData = images[edit.space.tabs[tabIndex].id] ?? nil
                    }
                    for archiveIndex in edit.space.archivedTabs.indices {
                        edit.space.archivedTabs[archiveIndex].tab.faviconData =
                            images[edit.space.archivedTabs[archiveIndex].id] ?? nil
                    }
                    BrowserCoreSessionEditing.apply(edit, to: &next, at: index)
                }
                if let removed = change.removedHistory {
                    let ids = Set(removed)
                    next.spaces[index].history.removeAll { ids.contains($0.id) }
                }
                if let entry = change.historyEntry {
                    next.spaces[index].history.removeAll { $0.id == entry.id }
                    next.spaces[index].history.insert(entry, at: 0)
                }
                if let removed = change.removedArchiveIndices {
                    let indices = Set(removed)
                    guard indices.allSatisfy({ next.spaces[index].archivedTabs.indices.contains($0) }) else {
                        throw CoreError.rejected(CREST_INVALID_ARGUMENT)
                    }
                    next.spaces[index].archivedTabs = next.spaces[index].archivedTabs.enumerated()
                        .filter { !indices.contains($0.offset) }.map(\.element)
                }
                if let groups = change.splitGroups { next.spaces[index].splitGroups = groups }
            }
            return (next, (!result.changes.isEmpty, result.selection ?? .none))
        }
    }

    func prepareTabBatch(
        _ request: BrowserTabBatchRequest, arguments: BrowserCoreTabBatch.Arguments, view: BrowserStoreSelection,
        at date: Date
    ) throws -> (command: PreparedChange, result: BrowserTabBatchResult) {
        let data = try JSONEncoder().encode(
            Command(
                operation: .tabsBatch, spaceId: request.assignment.spaceID.rawValue,
                profileId: request.assignment.profileID, arguments: arguments, view: View(view, in: projection),
                now: date.timeIntervalSinceReferenceDate))
        let handle = try prepareCommand(data)
        do {
            let response = try JSONDecoder().decode(BrowserCoreTabBatch.Response.self, from: readCommand(handle))
            let prepared = try BrowserCoreTabBatch.applying(response, to: projection)
            return (
                PreparedChange(handle: handle, session: prepared.session, hint: response.selection ?? .none),
                prepared.result
            )
        } catch {
            crest_session_release_command(handle)
            throw error
        }
    }

    func prepareSpace<Arguments: Encodable>(
        _ operation: BrowserSessionOperation, in spaceID: SpaceID?, arguments: Arguments,
        view: BrowserStoreSelection, at date: Date
    ) throws -> PreparedChange {
        let space = spaceID.flatMap { projection.space(id: $0) }
        let data = try JSONEncoder().encode(
            Command(
                operation: operation, spaceId: spaceID?.rawValue, profileId: space?.profile.id,
                arguments: arguments, view: View(view, in: projection), now: date.timeIntervalSinceReferenceDate))
        let handle = try prepareCommand(data)
        do {
            let next = try decodeMetadataProjection(readCommand(handle))
            return PreparedChange(handle: handle, session: next.session, hint: next.selection ?? .none)
        } catch {
            crest_session_release_command(handle)
            throw error
        }
    }

    func prepareWorkspace(_ request: BrowserCoreWorkspaceImport.Request, view: BrowserStoreSelection) throws
        -> PreparedChange
    {
        let input = try JSONEncoder().encode(
            WorkspaceImportCommand(
                mode: request.mode, arguments: request.arguments, view: View(view, in: projection),
                now: Date.now.timeIntervalSinceReferenceDate))
        let handle = try prepareCommand(input)
        do {
            let result = try JSONDecoder().decode(BrowserCoreWorkspaceImport.Result.self, from: readCommand(handle))
            let next = try result.materialize(existing: projection, request: request)
            return PreparedChange(handle: handle, session: next, hint: result.selection ?? .none)
        } catch {
            crest_session_release_command(handle)
            throw error
        }
    }

    /// Commits a prepared command and saves it before publishing, with the sync
    /// transaction's journal when one is given. A failed save leaves the
    /// projection and the accepted revision unchanged.
    func commitDurably(_ command: PreparedChange, sync: BrowserCoreSyncTransaction? = nil) throws {
        var accepted: UInt64 = 0
        let result = crest_session_commit_command_durably(command.handle, sync?.handle ?? 0, &accepted)
        guard result == CREST_OK else { throw CoreError(result) }
        revision = accepted
        projection = command.session
    }

    // MARK: - Actions - Core calls

    private func decodeMetadataProjection(_ output: Data) throws -> MetadataProjection {
        var next = try JSONDecoder().decode(MetadataProjection.self, from: output)
        for index in next.session.spaces.indices {
            guard let existing = projection.space(id: next.session.spaces[index].id) else { continue }
            guard next.session.spaces[index].profile == existing.profile else {
                throw CoreError.rejected(CREST_INVALID_ARGUMENT)
            }
            // The command keeps these collections in the core. Reattach native
            // read models and image assets without moving them across the ABI.
            next.session.spaces[index].tabs = existing.tabs
            next.session.spaces[index].folders = existing.folders
            next.session.spaces[index].history = existing.history
            next.session.spaces[index].archivedTabs = existing.archivedTabs
        }
        return next
    }

    private func commitCommand<Result>(
        _ data: Data,
        decode: (Data) throws -> (BrowserSession, Result)
    ) throws -> Result {
        let command = try prepareCommand(data)
        defer { crest_session_release_command(command) }
        let output = try readCommand(command)
        let (next, result) = try decode(output)
        var accepted: UInt64 = 0
        let committed = crest_session_commit_command(command, &accepted)
        guard committed == CREST_OK else { throw CoreError.rejected(committed) }
        revision = accepted
        projection = next
        return result
    }

    private func prepareCommand(_ data: Data) throws -> UInt64 {
        var command: UInt64 = 0
        let prepared = data.withUnsafeBytes {
            crest_session_prepare_command(
                owner.value, revision, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &command)
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
    /// Applies one `preferences.*` command. Only the preference record changes,
    /// so window selection and Space records stay exactly as projected.
    func executePreferences(_ request: BrowserAppPreferenceRequest) throws -> Bool {
        try commitCommand(try JSONEncoder().encode(request)) { output in
            var next = self.projection
            next.appPreferences = try JSONDecoder().decode(PreferencesResult.self, from: output).preferences
            return (next, next != self.projection)
        }
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
