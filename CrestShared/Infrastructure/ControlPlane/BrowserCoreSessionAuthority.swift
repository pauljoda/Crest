#if CREST_CORE_BACKED
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

    init(session: BrowserSession, workspaceKind: String = "persistent") {
        projection = session
        do {
            guard var input = try Self.value(Self.compact(session)) as? [String: Any] else {
                throw CoreError.rejected(CREST_INVALID_ARGUMENT)
            }
            input["coreWorkspaceKind"] = workspaceKind
            let data = try JSONSerialization.data(withJSONObject: input)
            var handle: UInt64 = 0; var initialRevision: UInt64 = 0
            let result = data.withUnsafeBytes {
                crest_session_create($0.bindMemory(to: UInt8.self).baseAddress, data.count, &handle, &initialRevision)
            }
            guard result == CREST_OK else { throw CoreError.rejected(result) }
            owner = SessionHandle(value: handle); revision = initialRevision
        } catch {
            preconditionFailure("Could not initialize the core session: \(error)")
        }
    }

    func replace(with next: BrowserSession) throws {
        if let data = try delta(to: next) {
            var accepted: UInt64 = 0
            let result = data.withUnsafeBytes {
                crest_session_commit(owner.value, revision, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &accepted)
            }
            guard result == CREST_OK else { throw CoreError.rejected(result) }
            revision = accepted
        }
        projection = next
    }

    /// The reservation excludes core writes until storage succeeds. A failed
    /// write releases it without changing the projection or accepted revision.
    func replaceDurably(with next: BrowserSession,
        sync: BrowserCoreSyncTransaction? = nil,
        persist: (any BrowserSessionCheckpoint) throws -> Void) throws {
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

    static func replacePair(
        source: BrowserCoreSessionAuthority, sourceSession: BrowserSession,
        destination: BrowserCoreSessionAuthority, destinationSession: BrowserSession
    ) throws {
        let empty = Data(#"{"version":1,"spaces":[]}"#.utf8)
        let a = try source.delta(to: sourceSession) ?? empty
        let b = try destination.delta(to: destinationSession) ?? empty
        var ar: UInt64 = 0; var br: UInt64 = 0
        let result = a.withUnsafeBytes { ap in b.withUnsafeBytes { bp in
            crest_session_commit_pair(source.owner.value, source.revision, ap.bindMemory(to: UInt8.self).baseAddress, a.count,
                destination.owner.value, destination.revision, bp.bindMemory(to: UInt8.self).baseAddress, b.count, &ar, &br)
        } }
        guard result == CREST_OK else { throw CoreError.rejected(result) }
        source.revision = ar; destination.revision = br
        // Both core graphs have committed before either window is reconciled.
        source.projection = sourceSession; destination.projection = destinationSession
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

    func prepareSpace(_ operation: String, in spaceID: SpaceID?, arguments: [String: Any],
        window: BrowserSession, at date: Date) throws -> PreparedSpace {
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
            let output = try readCommand(handle)
            struct Result: Decodable { let session: BrowserSession }
            var next = try JSONDecoder().decode(Result.self, from: output).session
            for index in next.spaces.indices {
                guard let existing = self.projection.space(id: next.spaces[index].id) else { continue }
                guard next.spaces[index].profile == existing.profile else { throw CoreError.rejected(CREST_INVALID_ARGUMENT) }
                // Space commands return only metadata for existing Spaces.
                // Collections and native assets are unchanged in the authority.
                next.spaces[index].tabs = existing.tabs
                next.spaces[index].folders = existing.folders
                next.spaces[index].history = existing.history
                next.spaces[index].archivedTabs = existing.archivedTabs
            }
            return PreparedSpace(handle: handle, session: next)
        } catch {
            crest_session_release_command(handle)
            throw error
        }
    }

    final class PreparedSpace {
        fileprivate let handle: UInt64
        let session: BrowserSession
        fileprivate init(handle: UInt64, session: BrowserSession) { self.handle = handle; self.session = session }
        deinit { crest_session_release_command(handle) }
    }

    func commitDurably(_ command: PreparedSpace, sync: BrowserCoreSyncTransaction? = nil,
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
        guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= 4 * 1024 * 1024 else {
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
#endif
