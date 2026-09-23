import CrestCoreABI
import Foundation
import Observation

/// The app's one connection to the core's typed application API.
///
/// `send` runs an intent and applies the changes it caused to `state` before
/// returning them, so a caller reads the new state straight away. A rule that
/// refuses an intent or a query throws its `Rejection`. Every other failure is
/// a build bug (a core and a Swift client built from different contracts) and
/// stops the app with a message naming the status.
@MainActor
@Observable
final class CrestCore {
    // MARK: - Variables

    /// The read model. Only the changes the core returns update it.
    let state = CoreState()
    @ObservationIgnored private let handle: UInt64

    // MARK: - Initializers

    /// A memory-only core. Nothing it holds is saved.
    init() {
        var handle: UInt64 = 0
        let status = CoreCodec.fingerprint.withUnsafeBufferPointer {
            crest_app_create($0.baseAddress, $0.count, &handle)
        }
        guard status == CREST_OK else { Self.buildBug(status, "create the core") }
        self.handle = handle
    }

    deinit {
        crest_app_destroy(handle)
    }

    // MARK: - Actions - Intents

    /// Runs one intent and returns the changes it caused, already applied to
    /// `state`. An intent that does not apply to the current state returns none.
    @discardableResult
    func send(_ intent: some Intent) throws(Rejection) -> [Change] {
        var writer = WireWriter()
        intent.encodeIntent(into: &writer)
        var reader = try call(crest_app_dispatch, writer, "send \(type(of: intent))")
        let changes: [Change]
        do {
            let count = try reader.readCount()
            var decoded: [Change] = []
            decoded.reserveCapacity(count)
            for _ in 0..<count { decoded.append(try Change(from: &reader)) }
            try reader.finish()
            changes = decoded
        } catch {
            preconditionFailure(
                "The core's changes for \(type(of: intent)) do not decode (\(error)). Rebuild the core.")
        }
        for change in changes { state.apply(change) }
        return changes
    }

    // MARK: - Actions - Queries

    func query<Question: Query>(_ query: Question) throws(Rejection) -> Question.Answer {
        var writer = WireWriter()
        query.encodeQuery(into: &writer)
        var reader = try call(crest_app_query, writer, "answer \(Question.self)")
        do {
            let answer = try Question.decodeAnswer(from: &reader)
            try reader.finish()
            return answer
        } catch {
            preconditionFailure("The core's answer to \(Question.self) does not decode (\(error)). Rebuild the core.")
        }
    }

    // MARK: - Actions - Boundary

    private typealias Entry = (UInt64, UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<crest_buffer_t>?) ->
        crest_status_t

    /// Calls one entry point and returns a reader over its answer, or throws
    /// the rejection it answered instead.
    private func call(_ entry: Entry, _ writer: WireWriter, _ action: @autoclosure () -> String) throws(Rejection)
        -> WireReader
    {
        var buffer = crest_buffer_t()
        let status = writer.bytes.withUnsafeBufferPointer { entry(handle, $0.baseAddress, $0.count, &buffer) }
        defer { crest_buffer_free(&buffer) }
        var reader = WireReader(buffer.bytes.map { Array(UnsafeBufferPointer(start: $0, count: buffer.length)) } ?? [])
        switch status {
        case CREST_OK:
            return reader
        case CREST_REJECTED:
            let rejection: Rejection
            do {
                rejection = try Rejection(from: &reader)
                try reader.finish()
            } catch {
                preconditionFailure("The core's rejection does not decode (\(error)). Rebuild the core.")
            }
            throw rejection
        default:
            Self.buildBug(status, action())
        }
    }

    private static func buildBug(_ status: crest_status_t, _ action: String) -> Never {
        let name =
            switch status {
            case CREST_INVALID_MESSAGE: "INVALID_MESSAGE"
            case CREST_INVALID_HANDLE: "INVALID_HANDLE"
            case CREST_VERSION_MISMATCH: "VERSION_MISMATCH"
            case CREST_INTERNAL_ERROR: "INTERNAL_ERROR"
            case CREST_INVALID_ARGUMENT: "INVALID_ARGUMENT"
            case CREST_LIMIT_EXCEEDED: "LIMIT_EXCEEDED"
            default: "status \(status)"
            }
        preconditionFailure(
            "The core could not \(action): \(name). The app and its core were built from different contracts; rebuild both."
        )
    }
}
