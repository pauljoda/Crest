#if CREST_CORE_BACKED
import CrestCoreABI
import Foundation

enum BrowserCoreSync {
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
