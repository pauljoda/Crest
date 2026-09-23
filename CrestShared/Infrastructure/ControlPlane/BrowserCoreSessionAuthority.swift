import CrestCoreABI
import Foundation
import Observation

/// One core session per store family. `projection` is the accepted native read
/// model, including native favicon assets; it cannot publish an unaccepted edit.
@Observable @MainActor
final class BrowserCoreSessionAuthority {
    private(set) var projection: BrowserSession
    @ObservationIgnored private var revision: UInt64
    @ObservationIgnored private let owner: SessionHandle
    @ObservationIgnored private var borrowedSource: BrowserCoreSessionAuthority?
    @ObservationIgnored private var borrowedSourceRevision: UInt64?

    init(session: BrowserSession, workspaceKind: String = "persistent", privateBrowsing: Bool = false) {
        projection = session
        do {
            guard var input = try Self.value(Self.compact(session)) as? [String: Any] else {
                throw CoreError.rejected(CREST_INVALID_ARGUMENT)
            }
            input["coreWorkspaceKind"] = workspaceKind
            input["corePrivateBrowsing"] = privateBrowsing || workspaceKind == "private"
            let data = try JSONSerialization.data(withJSONObject: input)
            var handle: UInt64 = 0; var initialRevision: UInt64 = 0
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
            owner = sessionOwner; revision = initialRevision
        } catch {
            preconditionFailure("Could not initialize the core session: \(error)")
        }
    }

    private init(owner: SessionHandle, revision: UInt64, projection: BrowserSession,
        borrowedSource: BrowserCoreSessionAuthority) {
        self.owner = owner; self.revision = revision; self.projection = projection
        self.borrowedSource = borrowedSource; borrowedSourceRevision = borrowedSource.revision
    }

    func makeBorrowed(in assignment: BrowserSpaceRuntimeAssignment) throws -> BrowserCoreSessionAuthority {
        let input = try JSONSerialization.data(withJSONObject: [
            "spaceId": assignment.spaceID.rawValue.uuidString, "profileId": assignment.profileID.uuidString])
        var handle: UInt64 = 0, initialRevision: UInt64 = 0, command: UInt64 = 0
        let status = input.withUnsafeBytes {
            crest_session_create_borrowed(owner.value, revision, $0.bindMemory(to: UInt8.self).baseAddress,
                input.count, &handle, &initialRevision, &command)
        }
        guard status == CREST_OK else { throw CoreError.rejected(status) }
        let child = SessionHandle(value: handle)
        defer { crest_session_release_command(command) }
        struct Result: Decodable { let session: BrowserSession }
        let session = try JSONDecoder().decode(Result.self, from: readCommand(command)).session
        return BrowserCoreSessionAuthority(owner: child, revision: initialRevision, projection: session, borrowedSource: self)
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
        let next = try decodeMetadataProjection(readCommand(command))
        var accepted: UInt64 = 0
        let committed = crest_session_commit_command(command, &accepted)
        guard committed == CREST_OK else { throw CoreError.rejected(committed) }
        revision = accepted; borrowedSourceRevision = borrowedSource.revision
        let changed = projection != next
        projection = next
        return changed
    }

    /// The reservation excludes core writes until storage succeeds. A failed
    /// write releases it without changing the projection or accepted revision.
    func replaceDurably(with proposed: BrowserSession,
        sync: BrowserCoreSyncTransaction? = nil,
        persist: (any BrowserSessionCheckpoint) throws -> Void) throws {
        let next = keepingPreferences(proposed)
        let delta = try delta(to: next) ?? Data(#"{"version":1,"spaces":[]}"#.utf8)
        let selection = try JSONSerialization.data(withJSONObject: Self.selection(for: next))
        var replacement: UInt64 = 0, checkpoint: UInt64 = 0
        let result = delta.withUnsafeBytes { bytes in selection.withUnsafeBytes { window in
            if let sync {
                return crest_session_reserve_sync_replacement(owner.value, revision, sync.handle,
                    bytes.bindMemory(to: UInt8.self).baseAddress, delta.count,
                    window.bindMemory(to: UInt8.self).baseAddress, selection.count, &replacement, &checkpoint)
            }
            return crest_session_reserve_replacement(owner.value, revision,
                bytes.bindMemory(to: UInt8.self).baseAddress, delta.count,
                window.bindMemory(to: UInt8.self).baseAddress, selection.count, &replacement, &checkpoint)
        } }
        guard result == CREST_OK else { throw CoreError.rejected(result) }
        defer { crest_session_release_replacement(replacement) }
        let snapshot = BrowserCoreSessionCheckpoint(handle: checkpoint)
        try persist(snapshot)
        var accepted: UInt64 = 0
        let committed = crest_session_commit_replacement(replacement, &accepted)
        // All validation and overflow checks precede the durable write. The
        // reservation makes publication infallible for this owned handle.
        precondition(committed == CREST_OK, "Lost core storage reservation")
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

    func prepareTabMove(_ tabID: TabID, source: BrowserSpaceRuntimeAssignment,
        destination: BrowserSpaceRuntimeAssignment, arguments: [String: Any], window: BrowserSession,
        at date: Date) throws -> PreparedChange {
        guard let moved = window.space(id: source.spaceID)?.tabs.first(where: { $0.id == tabID })
        else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "operation": "tab.transfer", "spaceId": source.spaceID.rawValue.uuidString,
            "profileId": source.profileID.uuidString, "destinationSpaceId": destination.spaceID.rawValue.uuidString,
            "destinationProfileId": destination.profileID.uuidString, "arguments": arguments,
            "window": Self.selection(for: window), "now": date.timeIntervalSinceReferenceDate
        ])
        let handle = try prepareCommand(data)
        do {
            let result = try JSONDecoder().decode(BrowserCoreTabTransfer.Result.self, from: readCommand(handle))
            let intermediate = try BrowserCoreTabTransfer.applying(result.source, to: window, moved: moved)
            let next = try BrowserCoreTabTransfer.applying(result.destination, to: intermediate, moved: moved,
                selectingSpace: arguments["select"] as? Bool == true)
            return PreparedChange(handle: handle, session: next)
        } catch { crest_session_release_command(handle); throw error }
    }

    static func prepareTransfer(source: BrowserCoreSessionAuthority, sourceWindow: BrowserSession,
        destination: BrowserCoreSessionAuthority, destinationWindow: BrowserSession,
        tabID: TabID, assignment: BrowserSpaceRuntimeAssignment, fallback: TabID?, selecting: Bool) throws -> PreparedTransfer {
        guard let moved = sourceWindow.space(id: assignment.spaceID)?.tabs.first(where: { $0.id == tabID })
        else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
        let input = try JSONSerialization.data(withJSONObject: [
            "version": 1, "spaceId": assignment.spaceID.rawValue.uuidString, "profileId": assignment.profileID.uuidString,
            "sourceWindow": selection(for: sourceWindow), "destinationWindow": selection(for: destinationWindow),
            "arguments": BrowserCoreTabTransfer.arguments(tabID: tabID, fallback: fallback, selecting: selecting),
            "now": Date.now.timeIntervalSinceReferenceDate
        ])
        var handle: UInt64 = 0
        let status = input.withUnsafeBytes { bytes in
            crest_session_prepare_transfer(source.owner.value, source.revision, destination.owner.value, destination.revision,
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
            return PreparedTransfer(handle: handle,
                source: try BrowserCoreTabTransfer.applying(result.source, to: sourceWindow, moved: moved),
                destination: try BrowserCoreTabTransfer.applying(result.destination, to: destinationWindow, moved: moved,
                    selectingSpace: selecting))
        } catch { crest_session_release_transfer(handle); throw error }
    }
    final class PreparedTransfer {
        fileprivate let handle: UInt64
        let source: BrowserSession
        let destination: BrowserSession
        fileprivate init(handle: UInt64, source: BrowserSession, destination: BrowserSession) {
            self.handle = handle; self.source = source; self.destination = destination
        }
        deinit { crest_session_release_transfer(handle) }
    }
    static func commitTransfer(_ prepared: PreparedTransfer,
        source: BrowserCoreSessionAuthority, destination: BrowserCoreSessionAuthority,
        sync: BrowserCoreSyncTransaction? = nil,
        persist: (any BrowserSessionCheckpoint, any BrowserSessionCheckpoint) throws -> Void) throws {
        var a: UInt64 = 0, b: UInt64 = 0
        let reserved = crest_session_reserve_transfer(prepared.handle, sync?.handle ?? 0, &a, &b)
        guard reserved == CREST_OK else { throw CoreError.rejected(reserved) }
        defer { crest_session_release_transfer(prepared.handle) }
        let sourceCheckpoint = BrowserCoreSessionCheckpoint(handle: a)
        let destinationCheckpoint = BrowserCoreSessionCheckpoint(handle: b)
        try persist(sourceCheckpoint, destinationCheckpoint)
        var ar: UInt64 = 0, br: UInt64 = 0
        let committed = crest_session_commit_transfer(prepared.handle, &ar, &br)
        precondition(committed == CREST_OK, "Lost core transfer reservation")
        source.revision = ar; destination.revision = br
        source.projection = prepared.source; destination.projection = prepared.destination
    }

    private static func selection(for window: BrowserSession) throws -> [String: Any] {
        [
            "selectedSpaceID": try Self.value(window.selectedSpaceID),
            "selectedTabs": try window.spaces.map { space -> [String: Any] in
                ["spaceID": try Self.value(space.id), "tabID": try space.selectedTabID.map(Self.value) ?? NSNull()]
            },
        ]
    }

    func execute(_ operation: String, in spaceID: SpaceID, arguments: [String: Any],
        window: BrowserSession, at date: Date) throws -> BrowserCoreSessionEditing.Result {
        guard let index = projection.spaces.firstIndex(where: { $0.id == spaceID }),
            let windowSpace = window.space(id: spaceID) else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "operation": operation, "spaceId": spaceID.rawValue.uuidString,
            "profileId": windowSpace.profile.id.uuidString,
            "arguments": arguments, "window": try Self.selection(for: window),
            "now": date.timeIntervalSinceReferenceDate,
        ])
        return try commitCommand(data) { output in
            let result = try BrowserCoreSessionEditing.decode(output, preservingAssetsFrom: self.projection.spaces[index])
            var next = self.projection
            next.selectedSpaceID = window.selectedSpaceID
            for i in next.spaces.indices {
                next.spaces[i].selectedTabID = window.space(id: next.spaces[i].id)?.selectedTabID
            }
            next.applyCoreResult(result, at: index)
            return (next, result)
        }
    }

    /// Image bytes are native assets. The command above owns their assignment;
    /// only its accepted tab identity can receive the bytes here.
    func applyFavicon(_ assignment: BrowserCoreSessionEditing.Result.FaviconAssignment?,
        bytes: Data?, in spaceID: SpaceID) -> TabID? {
        guard let index = projection.spaces.firstIndex(where: { $0.id == spaceID }) else { return nil }
        return projection.applyCoreFavicon(assignment, bytes: bytes, at: index)
    }

    func executeSpace(_ operation: String, in spaceID: SpaceID?, arguments: [String: Any],
        window: BrowserSession, at date: Date) throws -> Bool {
        let prepared = try prepareSpace(operation, in: spaceID, arguments: arguments, window: window, at: date)
        var accepted: UInt64 = 0
        let result = crest_session_commit_command(prepared.handle, &accepted)
        guard result == CREST_OK else { throw CoreError.rejected(result) }
        revision = accepted
        projection = prepared.session
        return projection != window
    }

    func executeRecords(_ operation: String, in spaceID: SpaceID?, arguments: [String: Any],
        window: BrowserSession, at date: Date) throws -> Bool {
        struct Changes: Decodable {
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
        }
        let space = spaceID.flatMap { window.space(id: $0) }
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "operation": operation,
            "spaceId": spaceID?.rawValue.uuidString as Any? ?? NSNull(),
            "profileId": space?.profile.id.uuidString as Any? ?? NSNull(),
            "arguments": arguments, "window": try Self.selection(for: window),
            "now": date.timeIntervalSinceReferenceDate,
        ])
        return try commitCommand(data) { output in
            let result = try JSONDecoder().decode(Changes.self, from: output)
            var next = self.projection
            next.selectedSpaceID = window.selectedSpaceID
            for index in next.spaces.indices {
                next.spaces[index].selectedTabID = window.space(id: next.spaces[index].id)?.selectedTabID
            }
            for change in result.changes {
                guard let index = next.spaces.firstIndex(where: { $0.id.rawValue == change.spaceId }),
                    next.spaces[index].profile.id == change.profileId else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
                let original = next.spaces[index]
                if var edit = change.tabEdit {
                    guard edit.space.id == original.id, edit.space.profile == original.profile else {
                        throw CoreError.rejected(CREST_INVALID_ARGUMENT)
                    }
                    var images = Dictionary(original.archivedTabs.map { ($0.id, $0.tab.faviconData) },
                        uniquingKeysWith: { first, _ in first })
                    for tab in original.tabs { images[tab.id] = tab.faviconData }
                    for tabIndex in edit.space.tabs.indices {
                        edit.space.tabs[tabIndex].faviconData = images[edit.space.tabs[tabIndex].id] ?? nil
                    }
                    for archiveIndex in edit.space.archivedTabs.indices {
                        edit.space.archivedTabs[archiveIndex].tab.faviconData = images[edit.space.archivedTabs[archiveIndex].id] ?? nil
                    }
                    next.applyCoreResult(edit, at: index)
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
            return (next, !result.changes.isEmpty)
        }
    }

    func prepareTabBatch(_ request: BrowserTabBatchRequest, arguments: [String: Any], window: BrowserSession,
        at date: Date) throws -> (command: PreparedChange, result: BrowserTabBatchResult) {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "operation": "tabs.batch", "spaceId": request.assignment.spaceID.rawValue.uuidString,
            "profileId": request.assignment.profileID.uuidString, "arguments": arguments,
            "window": try Self.selection(for: window), "now": date.timeIntervalSinceReferenceDate
        ])
        let handle = try prepareCommand(data)
        do {
            let response = try JSONDecoder().decode(BrowserCoreTabBatch.Response.self, from: readCommand(handle))
            var current = projection
            current.selectedSpaceID = window.selectedSpaceID
            for i in current.spaces.indices { current.spaces[i].selectedTabID = window.space(id: current.spaces[i].id)?.selectedTabID }
            let prepared = try BrowserCoreTabBatch.applying(response, to: current)
            return (PreparedChange(handle: handle, session: prepared.session), prepared.result)
        } catch { crest_session_release_command(handle); throw error }
    }

    func prepareSpace(_ operation: String, in spaceID: SpaceID?, arguments: [String: Any],
        window: BrowserSession, at date: Date) throws -> PreparedChange {
        let space = spaceID.flatMap { window.space(id: $0) }
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "operation": operation,
            "spaceId": spaceID?.rawValue.uuidString as Any? ?? NSNull(),
            "profileId": space?.profile.id.uuidString as Any? ?? NSNull(),
            "arguments": arguments, "window": try Self.selection(for: window),
            "now": date.timeIntervalSinceReferenceDate,
        ])
        let handle = try prepareCommand(data)
        do {
            let next = try decodeMetadataProjection(readCommand(handle))
            return PreparedChange(handle: handle, session: next)
        } catch {
            crest_session_release_command(handle)
            throw error
        }
    }

    private func decodeMetadataProjection(_ output: Data) throws -> BrowserSession {
        struct Result: Decodable { let session: BrowserSession }
        var next = try JSONDecoder().decode(Result.self, from: output).session
        for index in next.spaces.indices {
            guard let existing = projection.space(id: next.spaces[index].id) else { continue }
            guard next.spaces[index].profile == existing.profile else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
            // The command keeps these collections in the core. Reattach native
            // read models and image assets without moving them across the ABI.
            next.spaces[index].tabs = existing.tabs
            next.spaces[index].folders = existing.folders
            next.spaces[index].history = existing.history
            next.spaces[index].archivedTabs = existing.archivedTabs
        }
        return next
    }

    func prepareWorkspace(_ request: BrowserCoreWorkspaceImport.Request, window: BrowserSession) throws -> PreparedChange {
        let input = try JSONSerialization.data(withJSONObject: [
            "version": 1, "operation": "workspace.import", "mode": request.mode,
            "arguments": request.arguments, "window": Self.selection(for: window),
            "now": Date.now.timeIntervalSinceReferenceDate
        ])
        let handle = try prepareCommand(input)
        do {
            let result = try JSONDecoder().decode(BrowserCoreWorkspaceImport.Result.self, from: readCommand(handle))
            let next = try result.materialize(existing: window, request: request)
            return PreparedChange(handle: handle, session: next)
        } catch { crest_session_release_command(handle); throw error }
    }

    final class PreparedChange {
        fileprivate let handle: UInt64
        let session: BrowserSession
        fileprivate init(handle: UInt64, session: BrowserSession) { self.handle = handle; self.session = session }
        deinit { crest_session_release_command(handle) }
    }

    func commitDurably(_ command: PreparedChange, sync: BrowserCoreSyncTransaction? = nil,
        persist: (any BrowserSessionCheckpoint) throws -> Void) throws {
        let selection = try JSONSerialization.data(withJSONObject: Self.selection(for: command.session))
        var replacement: UInt64 = 0, checkpoint: UInt64 = 0
        let reserved = selection.withUnsafeBytes {
            crest_session_reserve_command(command.handle, $0.bindMemory(to: UInt8.self).baseAddress,
                selection.count, &replacement, &checkpoint)
        }
        guard reserved == CREST_OK else { throw CoreError.rejected(reserved) }
        defer { crest_session_release_replacement(replacement) }
        let snapshot = BrowserCoreSessionCheckpoint(handle: checkpoint)
        if let sync {
            let bound = crest_session_bind_sync_replacement(replacement, sync.handle)
            guard bound == CREST_OK else { throw CoreError.rejected(bound) }
        }
        try persist(snapshot)
        var accepted: UInt64 = 0
        precondition(crest_session_commit_replacement(replacement, &accepted) == CREST_OK,
            "Lost core command storage reservation")
        revision = accepted
        projection = command.session
    }

    private func commitCommand<Result>(_ data: Data,
        decode: (Data) throws -> (BrowserSession, Result)) throws -> Result {
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
            crest_session_prepare_command(owner.value, revision, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &command)
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

    func checkpoint(for window: BrowserSession) throws -> BrowserCoreSessionCheckpoint {
        let data = try JSONSerialization.data(withJSONObject: Self.selection(for: window))
        var handle: UInt64 = 0
        let result = data.withUnsafeBytes {
            crest_session_checkpoint(owner.value, revision, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &handle)
        }
        guard result == CREST_OK else { throw CoreError.rejected(result) }
        return BrowserCoreSessionCheckpoint(handle: handle)
    }

    private func delta(to next: BrowserSession) throws -> Data? {
        var result: [String: Any] = ["version": 1]
        var oldHeader = projection; oldHeader.spaces = []
        var newHeader = next; newHeader.spaces = []
        if oldHeader != newHeader { result["metadata"] = try Self.value(newHeader) }
        if projection.spaces.map(\.id) != next.spaces.map(\.id) {
            result["spaceOrder"] = next.spaces.map { $0.id.rawValue.uuidString }
        }
        let oldSpaces = Dictionary(uniqueKeysWithValues: projection.spaces.map { ($0.id, $0) })
        var changes: [[String: Any]] = []
        for space in next.spaces {
            let previous = oldSpaces[space.id]
            guard previous != space else { continue }
            var change: [String: Any] = ["id": space.id.rawValue.uuidString]
            let metadata = Self.metadata(space)
            if previous.map(Self.metadata) != metadata { change["metadata"] = try Self.value(metadata) }
            if let edit = try Self.collection(previous?.tabs.map(Self.compactTab) ?? [], space.tabs.map(Self.compactTab), id: { $0.id.rawValue }) {
                change["tabs"] = edit
            }
            if let edit = try Self.collection(previous?.folders ?? [], space.folders, id: { $0.id.rawValue }) { change["folders"] = edit }
            if let edit = try Self.collection(previous?.history ?? [], space.history, id: { $0.id }) { change["history"] = edit }
            if let edit = try Self.collection(previous?.archivedTabs.map(Self.compactArchive) ?? [], space.archivedTabs.map(Self.compactArchive), id: { $0.id.rawValue }) {
                change["archivedTabs"] = edit
            }
            if change.count > 1 { changes.append(change) }
        }
        if changes.isEmpty && result.count == 1 { return nil }
        result["spaces"] = changes
        return try JSONSerialization.data(withJSONObject: result)
    }

    private static func collection<T: Encodable & Equatable>(_ previous: [T], _ next: [T], id: (T) -> UUID) throws -> [String: Any]? {
        guard previous != next else { return nil }
        let oldIDs = previous.map(id); let nextIDs = next.map(id)
        // Older archives may contain repeated identities. Preserve their exact
        // order and contents until an archive operation explicitly changes them.
        guard Set(oldIDs).count == oldIDs.count, Set(nextIDs).count == nextIDs.count else {
            return ["replace": try value(next)]
        }
        let old = Dictionary(uniqueKeysWithValues: zip(oldIDs, previous))
        let retained = Set(nextIDs)
        var result: [String: Any] = [
            "remove": oldIDs.filter { !retained.contains($0) }.map(\.uuidString),
            "upsert": try next.filter { old[id($0)] != $0 }.map(value),
        ]
        if oldIDs != nextIDs { result["order"] = nextIDs.map(\.uuidString) }
        return result
    }
    private static func value<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
    }
    private nonisolated static func compactTab(_ source: BrowserTab) -> BrowserTab { var tab = source; tab.faviconData = nil; return tab }
    private nonisolated static func compactArchive(_ source: ArchivedTab) -> ArchivedTab { var entry = source; entry.tab.faviconData = nil; return entry }
    private static func metadata(_ source: BrowserSpace) -> BrowserSpace {
        var space = source; space.tabs = []; space.folders = []; space.history = []; space.archivedTabs = []; return space
    }
    nonisolated static func compact(_ source: BrowserSession) -> BrowserSession {
        var session = source
        for i in session.spaces.indices {
            session.spaces[i].tabs = session.spaces[i].tabs.map(compactTab)
            session.spaces[i].archivedTabs = session.spaces[i].archivedTabs.map(compactArchive)
        }
        return session
    }
    private enum CoreError: Error { case rejected(Int32) }
    private final class SessionHandle: Sendable {
        let value: UInt64
        init(value: UInt64) { self.value = value }
        deinit { crest_session_destroy(value) }
    }
}

// MARK: - App preferences

extension BrowserCoreSessionAuthority {
    /// Applies one `preferences.*` command. Only the preference record changes,
    /// so window selection and Space records stay exactly as projected.
    func executePreferences(_ request: BrowserAppPreferenceRequest) throws -> Bool {
        try commitCommand(try JSONEncoder().encode(request)) { output in
            struct Result: Decodable { let preferences: BrowserAppPreferences }
            var next = self.projection
            next.appPreferences = try JSONDecoder().decode(Result.self, from: output).preferences
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
    func read(_ request: [String: Any]) throws -> Data {
        let command = try prepareCommand(try JSONSerialization.data(withJSONObject: request))
        defer { crest_session_release_command(command) }
        return try readCommand(command)
    }
}

/// Retains a core revision, not a live session handle. Reading its parts does
/// not block newer edits and remains valid after the originating window closes.
final class BrowserCoreSessionCheckpoint: BrowserSessionCheckpoint, Sendable {
    private let handle: UInt64
    init(handle: UInt64) { self.handle = handle }
    deinit { crest_session_release_checkpoint(handle) }
    func coreData() -> Data? { read("core") }
    func historyData(in spaceID: SpaceID) -> Data? { read(spaceID.rawValue.uuidString) }
    private func read(_ part: String) -> Data? {
        let key = Data(part.utf8)
        var length = 0
        let measured = key.withUnsafeBytes {
            crest_session_read_checkpoint(handle, $0.bindMemory(to: UInt8.self).baseAddress, key.count, nil, 0, &length)
        }
        guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= 64 * 1024 * 1024 else { return nil }
        let capacity = length
        var output = Data(count: capacity)
        let result = output.withUnsafeMutableBytes { target in key.withUnsafeBytes { source in
            crest_session_read_checkpoint(handle, source.bindMemory(to: UInt8.self).baseAddress, key.count,
                target.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
        } }
        return result == CREST_OK ? output : nil
    }
}
