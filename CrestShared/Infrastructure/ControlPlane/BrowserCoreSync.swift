import CrestCoreABI
import Foundation

enum BrowserCoreSync {
    // MARK: - Types

    /// A sync query or stateless sync evaluation: the version and operation,
    /// then the operation's own members at the same level.
    struct Request<Arguments: Encodable>: Encodable {
        private enum CodingKeys: String, CodingKey {
            case version
            case operation
        }

        let operation: BrowserSyncOperation
        let arguments: Arguments

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .version)
            try container.encode(operation, forKey: .operation)
            try arguments.encode(to: encoder)
        }
    }

    /// A journal mutation: its operation and arguments, with the preferences a
    /// detached journal snapshot applies them under. The session's sync
    /// authority already holds its preferences.
    struct Mutation<Arguments: Encodable>: Encodable {
        let version = 1
        let operation: BrowserSyncOperation
        var preferences: BrowserSyncPreferences?
        let arguments: Arguments
    }

    /// A journal mutation's `arguments` for `stage`.
    struct StageArguments: Encodable {
        let session: BrowserSession
        let deletionReason: SyncDeletionReason
        let now: TimeInterval

        init(session: BrowserSession, deletionReason: SyncDeletionReason, at date: Date) {
            self.session = BrowserCoreSessionAuthority.compact(session)
            self.deletionReason = deletionReason
            now = date.timeIntervalSinceReferenceDate
        }
    }

    /// A journal mutation's `arguments` for `overwrite`.
    struct OverwriteArguments: Encodable {
        let session: BrowserSession
        let records: [BrowserSyncRecord]
        let now: TimeInterval

        init(session: BrowserSession, records: [BrowserSyncRecord], at date: Date) {
            self.session = BrowserCoreSessionAuthority.compact(session)
            self.records = records
            now = date.timeIntervalSinceReferenceDate
        }
    }

    /// A journal mutation's `arguments` for `merge` and `replace`.
    struct RecordsArguments: Encodable {
        let records: [BrowserSyncRecord]
    }

    /// A journal mutation's `arguments` for `acknowledge`.
    struct AcknowledgementArguments: Encodable {
        /// One uploaded record, with the version the service accepted when known.
        struct Acknowledgement: Encodable {
            let id: BrowserSyncRecordID
            var version: BrowserSyncVersion?
        }

        let acknowledgements: [Acknowledgement]

        init(_ recordIDs: Set<BrowserSyncRecordID>) {
            acknowledgements = recordIDs.map { Acknowledgement(id: $0) }
        }

        init(_ versions: [BrowserSyncRecordID: BrowserSyncVersion]) {
            acknowledgements = versions.map { Acknowledgement(id: $0.key, version: $0.value) }
        }
    }

    /// A materialization of a proposed session against sync records, as the
    /// journal's session preparation and the sync authority read it.
    struct SessionPreparation: Encodable {
        let session: BrowserSession
        let records: [BrowserSyncRecord]
        var preferences: BrowserSyncPreferences?
        let now: TimeInterval
        var emptySpace: BrowserSpace?
    }

    private struct MaterializeRequest: Encodable {
        let session: BrowserSession
        let preferences: BrowserSyncPreferences
        let records: [BrowserSyncRecord]
        let now: TimeInterval
        var emptySpace: BrowserSpace?
    }

    private struct RepairRequest: Encodable {
        let session: BrowserSession
        let now: TimeInterval
        var emptySpace: BrowserSpace?
    }

    private struct ProjectRequest: Encodable {
        let session: BrowserSession
        let preferences: BrowserSyncPreferences
        let records: [BrowserSyncRecord]
    }

    private struct ResolveRequest: Encodable {
        let first: BrowserSyncRecord
        let second: BrowserSyncRecord
    }

    private struct RepairedSession: Decodable {
        let session: BrowserSession
        let assets: [AssetSource]
    }

    private struct AssetSource: Decodable {
        let spaceIndex: Int
        let tabIndex: Int
        let sourceSpaceID: SpaceID
        let sourceTabID: TabID
    }

    private struct QueryResult<Value: Decodable>: Decodable {
        let value: Value?
        let error: QueryError?
    }

    private struct QueryError: Decodable {
        let code: BrowserCoreErrorCode
        let value: String
    }

    private enum CoreSyncError: Error {
        case tooLarge
        case rejected(Int32)
    }

    // MARK: - Actions - Sessions

    static func materialize(
        _ session: BrowserSession, preferences: BrowserSyncPreferences,
        records: [BrowserSyncRecord]
    ) throws -> BrowserSession {
        let request = MaterializeRequest(
            session: BrowserCoreSessionAuthority.compact(session), preferences: preferences, records: records,
            now: Date.now.timeIntervalSinceReferenceDate,
            emptySpace: session.spaces.isEmpty ? BrowserSession.makeBlankSpace(number: 1) : nil)
        let result: RepairedSession = try query(.materialize, request)
        return try reattachingAssets(result, from: session, byPosition: false)
    }

    static func repair(_ session: BrowserSession) throws -> BrowserSession {
        let request = RepairRequest(
            session: BrowserCoreSessionAuthority.compact(session), now: Date.now.timeIntervalSinceReferenceDate,
            emptySpace: session.spaces.isEmpty ? BrowserSession.makeBlankSpace(number: 1) : nil)
        let result: RepairedSession = try query(.sessionRepair, request)
        return try reattachingAssets(result, from: session, byPosition: true)
    }

    static func consumeMaterializedSession(_ handle: UInt64, from source: BrowserSession) throws -> BrowserSession {
        let repaired: RepairedSession = try readQuery(handle)
        return try reattachingAssets(repaired, from: source, byPosition: false)
    }

    private static func reattachingAssets(_ repaired: RepairedSession, from source: BrowserSession, byPosition: Bool)
        throws -> BrowserSession
    {
        var result = repaired.session
        let bySpace = Dictionary(source.spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byTab = bySpace.mapValues { space in
            Dictionary(space.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        for asset in repaired.assets {
            let si = asset.spaceIndex
            let ti = asset.tabIndex
            guard result.spaces.indices.contains(si), result.spaces[si].tabs.indices.contains(ti)
            else { throw CoreSyncError.rejected(CREST_INVALID_MESSAGE) }
            let original: BrowserTab?
            if byPosition {
                original =
                    source.spaces.indices.contains(si) && source.spaces[si].tabs.indices.contains(ti)
                    ? source.spaces[si].tabs[ti] : nil
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

    static func project(
        _ session: BrowserSession, preferences: BrowserSyncPreferences,
        records: [BrowserSyncRecord]
    ) throws -> [BrowserSyncPayload] {
        let payloads: [BrowserSyncPayload] = try query(
            .project,
            ProjectRequest(
                session: BrowserCoreSessionAuthority.compact(session), preferences: preferences, records: records))
        for payload in payloads { try payload.validate() }
        return payloads
    }

    static func resolve(_ first: BrowserSyncRecord, _ second: BrowserSyncRecord) throws -> BrowserSyncRecord {
        try first.validate()
        try second.validate()
        let result: BrowserSyncRecord = try evaluate(.resolve, ResolveRequest(first: first, second: second))
        try result.validate()
        guard result.id == first.id, result.spaceID == first.spaceID else {
            throw BrowserSyncError.recordIdentityMismatch(first.id.recordName)
        }
        return result
    }

    // MARK: - Actions - Core calls

    static func query<Arguments: Encodable, Result: Decodable>(
        _ operation: BrowserSyncOperation, _ arguments: Arguments
    ) throws -> Result {
        let input = try JSONEncoder().encode(Request(operation: operation, arguments: arguments))
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
        guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= limit else {
            throw CoreSyncError.rejected(measured)
        }
        let capacity = length
        var output = Data(count: capacity)
        let read = output.withUnsafeMutableBytes {
            crest_sync_query_read(handle, $0.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
        }
        guard read == CREST_OK, length <= capacity else { throw CoreSyncError.rejected(read) }
        let response = try JSONDecoder().decode(QueryResult<Result>.self, from: output.prefix(length))
        if let error = response.error { throw syncError(error) }
        guard let value = response.value else { throw CoreSyncError.rejected(CREST_INVALID_MESSAGE) }
        return value
    }

    static func evaluate<Arguments: Encodable, Result: Decodable>(
        _ operation: BrowserSyncOperation, _ arguments: Arguments
    ) throws -> Result {
        let input = try JSONEncoder().encode(Request(operation: operation, arguments: arguments))
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
                crest_core_evaluate_sync(
                    source.bindMemory(to: UInt8.self).baseAddress, input.count,
                    destination.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
            }
        }
        guard result == CREST_OK, length <= capacity else { throw CoreSyncError.rejected(result) }
        return try JSONDecoder().decode(Result.self, from: output.prefix(length))
    }

    /// The sync failure a query's error names. A code whose value this build
    /// cannot read, or that it does not know, is a change the core did not apply.
    private static func syncError(_ error: QueryError) -> BrowserSyncError {
        switch error.code {
        case .duplicateRecord:
            return .duplicateRecord(error.value)
        case .invalidFolderHierarchy:
            if let id = UUID(uuidString: error.value) { return .invalidFolderHierarchy(SpaceID(rawValue: id)) }
        case .recordLimitExceeded:
            if let count = Int(error.value) { return .recordLimitExceeded(count) }
        case .duplicateProfile:
            if let id = UUID(uuidString: error.value) { return .duplicateProfile(id) }
        case .immutableProfileChanged:
            if let id = UUID(uuidString: error.value) { return .immutableProfileChanged(SpaceID(rawValue: id)) }
        case .danglingFolder:
            if let id = UUID(uuidString: error.value) { return .danglingFolder(TabID(rawValue: id)) }
        case .tooManyPinnedTabs:
            if let id = UUID(uuidString: error.value) { return .tooManyPinnedTabs(SpaceID(rawValue: id)) }
        default:
            break
        }
        return .remoteChangeNotApplied(error.code.rawValue)
    }
}
