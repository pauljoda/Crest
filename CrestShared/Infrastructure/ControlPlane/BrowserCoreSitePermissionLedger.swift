import CrestCoreABI
import Foundation
import os

/// Handle to one process-local core site permission ledger. The core owns
/// the per-Space choices, their lookup, listing order and which choices are
/// saved; this wrapper only moves JSON across the boundary. Nil means the core
/// rejected the command or could not answer, and every caller fails closed.
final class BrowserCoreSitePermissionLedger {
    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "CorePermissions")
    private let handle: UInt64

    init() {
        var value: UInt64 = 0
        precondition(crest_permissions_create(&value) == CREST_OK, "Could not initialize the site permission ledger")
        handle = value
    }

    deinit { crest_permissions_destroy(handle) }

    /// The raw JSON answer to one v1 command.
    func apply(_ command: String, _ arguments: [String: Any]) -> Data? {
        var request = arguments
        request["version"] = 1
        request["command"] = command
        guard let data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        var length = 0
        let applied = data.withUnsafeBytes {
            crest_permissions_apply(handle, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &length)
        }
        guard applied == CREST_OK, length > 0 else {
            Self.logger.error("Core permission ledger rejected \(command, privacy: .public): \(applied)")
            return nil
        }
        var output = Data(count: length)
        let capacity = length
        let read = output.withUnsafeMutableBytes {
            crest_permissions_read(handle, $0.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
        }
        guard read == CREST_OK else {
            Self.logger.error("Core permission ledger output failed: \(read)")
            return nil
        }
        return output
    }
}
