import CloudKit
import Foundation

enum BrowserCloudRecordCodecError: Error, Equatable {
    /// The server's last copy of a record is another record's.
    case mismatchedBaseRecord(String)
    /// A newer build wrote the server's last copy for a schema this build
    /// does not know, so this build must not write over it.
    case newerSchema(Int)
}
