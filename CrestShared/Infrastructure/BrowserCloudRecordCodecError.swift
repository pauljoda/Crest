import CloudKit
import Foundation

enum BrowserCloudRecordCodecError: Error, Equatable {
    case unexpectedZone(String)
    case unexpectedRecordType(String)
    case malformedRecordName(String)
    case mismatchedBaseRecord(String)
    case missingField(String)
    case invalidField(String)
    case payloadEncodingFailed
    case payloadDecodingFailed
}
