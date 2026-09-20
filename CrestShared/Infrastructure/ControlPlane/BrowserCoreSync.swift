#if CREST_CORE_BACKED
import CrestCoreABI
import Foundation

enum BrowserCoreSync {
    static func materialize(_ session: BrowserSession, preferences: BrowserSyncPreferences,
                            records: [BrowserSyncRecord]) throws -> BrowserSession {
        var request: [String: Any] = [
            "version": 1, "operation": "materialize", "session": try value(BrowserCoreSessionAuthority.compact(session)),
            "preferences": try value(preferences), "records": try value(records), "now": Date.now.timeIntervalSinceReferenceDate
        ]
        if session.spaces.isEmpty { request["emptySpace"] = try value(BrowserSession.makeBlankSpace(number: 1)) }
        let result: RepairedSession = try query(request)
        return try reattachingAssets(result, from: session, byPosition: false)
    }

    static func repair(_ session: BrowserSession) throws -> BrowserSession {
        var request: [String: Any] = [
            "version": 1, "operation": "session.repair", "session": try value(BrowserCoreSessionAuthority.compact(session)),
            "now": Date.now.timeIntervalSinceReferenceDate
        ]
        if session.spaces.isEmpty { request["emptySpace"] = try value(BrowserSession.makeBlankSpace(number: 1)) }
        let result: RepairedSession = try query(request)
        return try reattachingAssets(result, from: session, byPosition: true)
    }

    static func retain(_ session: BrowserSession, at date: Date) throws -> (session: BrowserSession, changed: Bool) {
        let retained: RetainedSession = try query([
            "version": 1, "operation": "session.retain", "session": try value(BrowserCoreSessionAuthority.compact(session)),
            "now": date.timeIntervalSinceReferenceDate
        ])
        var result = retained.session
        // Retention changes only history/archive, so live assets retain their
        // exact positional ownership, including deliberately empty windows.
        guard result.spaces.count == session.spaces.count else { throw CoreSyncError.rejected(CREST_INVALID_MESSAGE) }
        for si in result.spaces.indices {
            guard result.spaces[si].id == session.spaces[si].id, result.spaces[si].tabs.count == session.spaces[si].tabs.count
            else { throw CoreSyncError.rejected(CREST_INVALID_MESSAGE) }
            for ti in result.spaces[si].tabs.indices {
                guard result.spaces[si].tabs[ti].id == session.spaces[si].tabs[ti].id else { throw CoreSyncError.rejected(CREST_INVALID_MESSAGE) }
                result.spaces[si].tabs[ti].faviconData = session.spaces[si].tabs[ti].faviconData
            }
            let archive = Dictionary(session.spaces[si].archivedTabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for ai in result.spaces[si].archivedTabs.indices {
                let id = result.spaces[si].archivedTabs[ai].id
                result.spaces[si].archivedTabs[ai].tab.faviconData = archive[id]?.tab.faviconData
            }
        }
        return (result, retained.changed)
    }

    private struct RetainedSession: Decodable { let session: BrowserSession; let changed: Bool }
    private struct RepairedSession: Decodable { let session: BrowserSession; let assets: [AssetSource] }
    private struct AssetSource: Decodable {
        let spaceIndex: Int
        let tabIndex: Int
        let sourceSpaceID: SpaceID
        let sourceTabID: TabID
    }

    static func consumeMaterializedSession(_ handle: UInt64, from source: BrowserSession) throws -> BrowserSession {
        let repaired: RepairedSession = try readQuery(handle)
        return try reattachingAssets(repaired, from: source, byPosition: false)
    }

    private static func reattachingAssets(_ repaired: RepairedSession, from source: BrowserSession, byPosition: Bool) throws -> BrowserSession {
        var result = repaired.session
        let bySpace = Dictionary(source.spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byTab = bySpace.mapValues { space in Dictionary(space.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
        for asset in repaired.assets {
            let si = asset.spaceIndex, ti = asset.tabIndex
            guard result.spaces.indices.contains(si), result.spaces[si].tabs.indices.contains(ti)
            else { throw CoreSyncError.rejected(CREST_INVALID_MESSAGE) }
            let original: BrowserTab?
            if byPosition {
                original = source.spaces.indices.contains(si) && source.spaces[si].tabs.indices.contains(ti) ? source.spaces[si].tabs[ti] : nil
            } else {
                original = byTab[asset.sourceSpaceID]?[asset.sourceTabID]
            }
            result.spaces[si].tabs[ti].faviconData = original?.faviconData
            if original?.faviconData != nil, result.spaces[si].tabs[ti].faviconURL == nil {
                result.spaces[si].tabs[ti].faviconURL = original?.url
            }
        }
        return result
    }

    static func project(_ session: BrowserSession, preferences: BrowserSyncPreferences,
                        records: [BrowserSyncRecord]) throws -> [BrowserSyncPayload] {
        let payloads: [BrowserSyncPayload] = try query([
            "version": 1, "operation": "project", "session": try value(BrowserCoreSessionAuthority.compact(session)),
            "preferences": try value(preferences), "records": try value(records)
        ])
        for payload in payloads { try payload.validate() }
        return payloads
    }

    static func query<Result: Decodable>(_ request: [String: Any]) throws -> Result {
        let input = try JSONSerialization.data(withJSONObject: request)
        let limit = 64 * 1024 * 1024
        guard input.count <= limit else { throw CoreSyncError.tooLarge }
        var handle: UInt64 = 0
        let prepared = input.withUnsafeBytes {
            crest_sync_query_prepare($0.bindMemory(to: UInt8.self).baseAddress, input.count, &handle)
        }
        guard prepared == CREST_OK else { throw CoreSyncError.rejected(prepared) }
        return try readQuery(handle)
    }

    /// Consumes a prepared result handle, including when decoding throws.
    static func readQuery<Result: Decodable>(_ handle: UInt64) throws -> Result {
        defer { crest_sync_query_release(handle) }
        let limit = 64 * 1024 * 1024
        var length = 0
        let measured = crest_sync_query_read(handle, nil, 0, &length)
        guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= limit else { throw CoreSyncError.rejected(measured) }
        let capacity = length
        var output = Data(count: capacity)
        let read = output.withUnsafeMutableBytes {
            crest_sync_query_read(handle, $0.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
        }
        guard read == CREST_OK, length <= capacity else { throw CoreSyncError.rejected(read) }
        let response = try JSONDecoder().decode(QueryResult<Result>.self, from: output.prefix(length))
        if let error = response.error {
            switch error.code {
            case "duplicateRecord": throw BrowserSyncError.duplicateRecord(error.value)
            case "invalidFolderHierarchy":
                if let id = UUID(uuidString: error.value) { throw BrowserSyncError.invalidFolderHierarchy(SpaceID(rawValue: id)) }
            case "recordLimitExceeded":
                if let count = Int(error.value) { throw BrowserSyncError.recordLimitExceeded(count) }
            case "duplicateProfile":
                if let id = UUID(uuidString: error.value) { throw BrowserSyncError.duplicateProfile(id) }
            case "immutableProfileChanged":
                if let id = UUID(uuidString: error.value) { throw BrowserSyncError.immutableProfileChanged(SpaceID(rawValue: id)) }
            case "danglingFolder":
                if let id = UUID(uuidString: error.value) { throw BrowserSyncError.danglingFolder(TabID(rawValue: id)) }
            case "tooManyPinnedTabs":
                if let id = UUID(uuidString: error.value) { throw BrowserSyncError.tooManyPinnedTabs(SpaceID(rawValue: id)) }
            default: break
            }
            throw BrowserSyncError.remoteChangeNotApplied(error.code)
        }
        guard let value = response.value else { throw CoreSyncError.rejected(CREST_INVALID_MESSAGE) }
        return value
    }

    private struct QueryResult<Value: Decodable>: Decodable {
        let value: Value?
        let error: QueryError?
    }
    private struct QueryError: Decodable { let code: String; let value: String }

    static func resolve(_ first: BrowserSyncRecord, _ second: BrowserSyncRecord) throws -> BrowserSyncRecord {
        try first.validate()
        try second.validate()
        let request: [String: Any] = [
            "version": 1, "operation": "resolve",
            "first": try value(first), "second": try value(second)
        ]
        let result: BrowserSyncRecord = try evaluate(request)
        try result.validate()
        guard result.id == first.id, result.spaceID == first.spaceID else {
            throw BrowserSyncError.recordIdentityMismatch(first.id.recordName)
        }
        return result
    }

    static func value<Value: Encodable>(_ value: Value) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }

    static func evaluate<Result: Decodable>(_ request: [String: Any]) throws -> Result {
        let input = try JSONSerialization.data(withJSONObject: request)
        let limit = 16 * 1024 * 1024
        guard input.count <= limit else { throw CoreSyncError.tooLarge }
        var length = 0
        let measured = input.withUnsafeBytes {
            crest_core_evaluate_sync($0.bindMemory(to: UInt8.self).baseAddress, input.count, nil, 0, &length)
        }
        guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= limit else {
            throw CoreSyncError.rejected(measured)
        }
        let capacity = length
        var output = Data(count: capacity)
        let result = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                crest_core_evaluate_sync(source.bindMemory(to: UInt8.self).baseAddress, input.count,
                    destination.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
            }
        }
        guard result == CREST_OK, length <= capacity else { throw CoreSyncError.rejected(result) }
        return try JSONDecoder().decode(Result.self, from: output.prefix(length))
    }

    private enum CoreSyncError: Error { case tooLarge, rejected(Int32) }
}
#endif
