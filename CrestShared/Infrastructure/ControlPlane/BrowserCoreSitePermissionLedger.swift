import CrestCoreABI
import Foundation
import os

/// Handle to one process-local core site permission ledger. The core owns
/// the per-Space choices, their lookup, listing order and which choices are
/// saved; this wrapper only moves JSON across the boundary. Nil means the core
/// rejected the command or could not answer, and every caller fails closed.
final class BrowserCoreSitePermissionLedger {
    // MARK: - Types

    /// One ledger command. Raw values are the core's spellings in
    /// `SitePermissionCommand.cs`.
    enum Command: String, Encodable, Sendable {
        case decision
        case load
        case mediaDecision = "media_decision"
        case records
        case resetRecord = "reset_record"
        case resetSession = "reset_session"
        case resetSpace = "reset_space"
        case set
    }

    /// Every ledger request: the version and command, then the command's own
    /// members at the same level.
    private struct Request<Arguments: Encodable>: Encodable {
        private enum CodingKeys: String, CodingKey {
            case version
            case command
        }

        let command: Command
        let arguments: Arguments

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .version)
            try container.encode(command, forKey: .command)
            try arguments.encode(to: encoder)
        }
    }

    // MARK: - Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "CorePermissions")
    private let handle: UInt64

    // MARK: - Initializers

    init() {
        var value: UInt64 = 0
        precondition(crest_permissions_create(&value) == CREST_OK, "Could not initialize the site permission ledger")
        handle = value
    }

    deinit { crest_permissions_destroy(handle) }

    // MARK: - Actions - Commands

    /// The raw JSON answer to one v1 command.
    func apply<Arguments: Encodable>(_ command: Command, _ arguments: Arguments) -> Data? {
        guard let data = try? JSONEncoder().encode(Request(command: command, arguments: arguments)) else {
            return nil
        }
        var length = 0
        let applied = data.withUnsafeBytes {
            crest_permissions_apply(handle, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &length)
        }
        guard applied == CREST_OK, length > 0 else {
            Self.logger.error("Core permission ledger rejected \(command.rawValue, privacy: .public): \(applied)")
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
