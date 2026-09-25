import Foundation

@testable import Crest

extension SyncRecord {
    /// TRANSITIONAL until slice 8c deletes the Swift sync journal: `record`, a
    /// record the Swift journal holds, as the cloud stores it, for tests that
    /// still build cloud records with the Swift journal's types.
    init(browser record: BrowserSyncRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let kind = SyncRecordKind.named(record.id.kind.rawValue),
            let body = try record.encodedPayload(using: encoder) ?? record.encodedTombstone(using: encoder)
        else { throw CocoaError(.coderInvalidValue) }
        self.init(
            kind: kind, id: record.id.value, spaceID: record.spaceID.rawValue,
            version: SyncVersion(clock: record.version.logicalClock, deviceID: record.version.deviceID), schema: 1, body: body,
            isTombstone: record.payload == nil)
    }
}
