import CrestCoreABI
import Foundation
import Observation
import Synchronization

/// The app's one connection to the core's typed application API.
///
/// `send` runs an intent and applies the changes it caused to `state` before
/// returning them, so a caller reads the new state straight away. The core
/// answers any changes still pending first, so an older change never lands
/// after a newer one. A rule that
/// refuses an intent or a query throws its `Rejection`. Every other failure is
/// a build bug (a core and a Swift client built from different contracts) and
/// stops the app with a message naming the status.
///
/// `query` may be called from any thread: it reads only the immutable handle,
/// the core serializes every call on one app, and a query never changes the
/// core's state or `state`. Intents stay on the main actor.
///
/// Changes the core starts itself, such as a finished save, arrive through a
/// payload-free wake that hops to the main queue and drains them, at most once
/// per main-queue turn.
@MainActor
@Observable
final class CrestCore {
    // MARK: - Variables

    /// The read model. Only the changes the core returns update it.
    let state = CoreState()
    /// The engines this core hosts pages on, which the composition registers.
    @ObservationIgnored private(set) lazy var engines = Engines(core: self)
    /// Where the core keeps `session.sqlite`; nil when it keeps everything in
    /// memory.
    let storageDirectory: URL?
    /// Called for each save the core started itself and could not finish.
    @ObservationIgnored var storageFailureHandler: ((StorageFailure) -> Void)?
    /// Called each time the core staged the session's edits in its sync
    /// journal, so the cloud transport can schedule an upload.
    @ObservationIgnored var syncJournalChangeHandler: (() -> Void)?
    @ObservationIgnored nonisolated let handle: UInt64
    @ObservationIgnored private let wake = CoreWakeRelay()
    /// Callers waiting for a revision to reach disk. A drain resumes them.
    @ObservationIgnored var saveWaiters: [(revision: Int64, continuation: CheckedContinuation<Void, Never>)] = []
    #if DEBUG
        /// Hears each batch of changes once `state` has applied it, so a test
        /// can apply the same batch again.
        @ObservationIgnored var batchApplied: (([Change]) -> Void)?
    #endif

    // MARK: - Initializers

    /// A memory-only core. Nothing it holds is saved.
    convenience init() {
        do {
            try self.init(configuration: AppConfiguration(storageDirectory: nil))
        } catch {
            preconditionFailure("A memory-only core refused to open: \(error). Rebuild the core.")
        }
    }

    /// A core configured once, at creation. With a storage directory the core
    /// opens the session file there; it throws the rejection naming why that
    /// file cannot be used.
    init(configuration: AppConfiguration) throws(Rejection) {
        var writer = WireWriter()
        configuration.encode(into: &writer)
        var handle: UInt64 = 0
        var refusal = crest_buffer_t()
        let status = CoreCodec.fingerprint.withUnsafeBufferPointer { fingerprint in
            writer.bytes.withUnsafeBufferPointer { settings in
                crest_app_create(
                    fingerprint.baseAddress, fingerprint.count, settings.baseAddress, settings.count, &handle, &refusal)
            }
        }
        defer { crest_buffer_free(&refusal) }
        switch status {
        case CREST_OK:
            self.handle = handle
        case CREST_REJECTED:
            throw Self.rejection(in: refusal)
        default:
            Self.buildBug(status, "create the core")
        }
        storageDirectory = configuration.storageDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        wake.core = self
        state.favicons.takePageImage = { [weak self] in self?.engines.takeIcon(of: $0) }
        let installed = crest_app_set_wake(handle, relayCoreWake, Unmanaged.passUnretained(wake).toOpaque())
        guard installed == CREST_OK else { Self.buildBug(installed, "set its wake callback") }
    }

    deinit {
        // No wake may reach the relay once the core is gone.
        crest_app_set_wake(handle, nil, nil)
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
        let changes = decodeChanges(from: &reader, "\(type(of: intent))")
        apply(changes)
        return changes
    }

    // MARK: - Actions - Queries

    nonisolated func query<Question: Query>(_ query: Question) throws(Rejection) -> Question.Answer {
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

    // MARK: - Actions - Changes

    /// Applies the changes the core started itself since the last drain, then
    /// answers the callers waiting for them.
    func drain() {
        var buffer = crest_buffer_t()
        let status = crest_app_drain(handle, &buffer)
        defer { crest_buffer_free(&buffer) }
        guard status == CREST_OK else { Self.buildBug(status, "drain its changes") }
        let length = buffer.length
        var reader = WireReader(buffer.bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? [])
        apply(decodeChanges(from: &reader, "its own work"))
        resumeSaveWaiters()
    }

    /// Applies one batch to `state`, in order, and reports a failed save the
    /// core started itself.
    private func apply(_ changes: [Change]) {
        var pageRecords = Engines.PageRecords()
        for change in changes {
            state.apply(change)
            switch change {
            case .storageFailed(let failure): storageFailed(failure.reason)
            case .syncJournalChanged: syncJournalChangeHandler?()
            case .navigationRecorded(let recorded): pageRecords.navigations.append(recorded)
            case .tabFaviconAssigned(let assigned) where assigned.pageID != nil: pageRecords.icons.append(assigned)
            default: break
            }
        }
        state.finishBatch(changes)
        if !pageRecords.isEmpty { engines.recordsApplied(pageRecords) }
        #if DEBUG
            batchApplied?(changes)
        #endif
    }

    /// Tells the core the main queue finished the turn a wake's drain followed,
    /// so the work it queued behind that turn, such as a sync stage, may start.
    func endTurn() {
        let status = crest_app_end_turn(handle)
        guard status == CREST_OK else { Self.buildBug(status, "end the main queue's turn") }
    }

    private func decodeChanges(from reader: inout WireReader, _ source: @autoclosure () -> String) -> [Change] {
        do {
            let count = try reader.readCount()
            var decoded: [Change] = []
            decoded.reserveCapacity(count)
            for _ in 0..<count { decoded.append(try Change(from: &reader)) }
            try reader.finish()
            return decoded
        } catch {
            preconditionFailure("The core's changes for \(source()) do not decode (\(error)). Rebuild the core.")
        }
    }

    // MARK: - Actions - Boundary

    private typealias Entry = (UInt64, UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<crest_buffer_t>?) ->
        crest_status_t

    /// Calls one entry point and returns a reader over its answer, or throws
    /// the rejection it answered instead.
    nonisolated private func call(
        _ entry: Entry, _ writer: WireWriter, _ action: @autoclosure () -> String
    ) throws(Rejection) -> WireReader {
        var buffer = crest_buffer_t()
        let status = writer.bytes.withUnsafeBufferPointer { entry(handle, $0.baseAddress, $0.count, &buffer) }
        defer { crest_buffer_free(&buffer) }
        switch status {
        case CREST_OK:
            return WireReader(buffer.bytes.map { Array(UnsafeBufferPointer(start: $0, count: buffer.length)) } ?? [])
        case CREST_REJECTED:
            throw Self.rejection(in: buffer)
        default:
            Self.buildBug(status, action())
        }
    }

    /// The one rejection a refused call left in `buffer`.
    nonisolated static func rejection(in buffer: crest_buffer_t) -> Rejection {
        let length = buffer.length
        var reader = WireReader(buffer.bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? [])
        do {
            let rejection = try Rejection(from: &reader)
            try reader.finish()
            return rejection
        } catch {
            preconditionFailure("The core's rejection does not decode (\(error)). Rebuild the core.")
        }
    }

    nonisolated static func buildBug(_ status: crest_status_t, _ action: String) -> Never {
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

/// Carries the core's wake from whichever thread published a change to one
/// drain on the main queue, which also ends the main queue's turn for the
/// core. A wake that finds a drain already queued adds nothing.
private final class CoreWakeRelay: Sendable {
    nonisolated(unsafe) weak var core: CrestCore?
    private let isScheduled = Atomic<Bool>(false)

    func schedule() {
        guard !isScheduled.exchange(true, ordering: .acquiringAndReleasing) else { return }
        DispatchQueue.main.async { [self] in
            isScheduled.store(false, ordering: .releasing)
            MainActor.assumeIsolated {
                core?.drain()
                core?.endTurn()
            }
        }
    }
}

/// The core's wake callback. It runs on the core thread that published a
/// change, outside every core lock, so it only schedules the drain.
private func relayCoreWake(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<CoreWakeRelay>.fromOpaque(context).takeUnretainedValue().schedule()
}
