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

    init(session: BrowserSession) {
        projection = session
        do {
            let data = try JSONEncoder().encode(Self.compact(session))
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

    func checkpoint(for window: BrowserSession) throws -> BrowserCoreSessionCheckpoint {
        let selection: [String: Any] = [
            "selectedSpaceID": try Self.value(window.selectedSpaceID),
            "selectedTabs": try window.spaces.map { space -> [String: Any] in
                ["spaceID": try Self.value(space.id), "tabID": try space.selectedTabID.map(Self.value) ?? NSNull()]
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: selection)
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
    private static func compactTab(_ source: BrowserTab) -> BrowserTab { var tab = source; tab.faviconData = nil; return tab }
    private static func compactArchive(_ source: ArchivedTab) -> ArchivedTab { var entry = source; entry.tab.faviconData = nil; return entry }
    private static func metadata(_ source: BrowserSpace) -> BrowserSpace {
        var space = source; space.tabs = []; space.folders = []; space.history = []; space.archivedTabs = []; return space
    }
    private static func compact(_ source: BrowserSession) -> BrowserSession {
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
