import CrestCoreABI
import Foundation

/// The platform's direct path to an engine binding written outside Swift, as
/// `EnginePage` uses it: requests for view work on a page, which the binding
/// answers at once, and the presentations it sends back when work finishes
/// later. Both cross the binding's `crest_engine_pages_t` table in the
/// generated wire format; the core never sees them.
@MainActor
final class NativeEnginePages {
    // MARK: - Variables

    private let table: crest_engine_pages_t
    /// Hears each presentation the binding sends.
    private let present: @MainActor (EnginePresentation) -> Void

    // MARK: - Initializers

    /// A path to the binding `table` names. The binding sends its
    /// presentations to `present` from now on; this object must outlive the
    /// binding, as the composition that owns it does.
    init(table: crest_engine_pages_t, present: @escaping @MainActor (EnginePresentation) -> Void) {
        self.table = table
        self.present = present
        guard let presentTo = table.present_to else {
            preconditionFailure("The engine binding has no way to present. Rebuild the engine.")
        }
        presentTo(table.context, receiveEnginePresentation, Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: - Actions - Requests

    /// Asks the binding for `request` and answers what it answered.
    @discardableResult
    func request<Request: PageRequest>(_ request: Request) -> Request.Answer {
        guard let send = table.request, let release = table.release else {
            preconditionFailure("The engine binding takes no requests. Rebuild the engine.")
        }
        var writer = WireWriter()
        request.encodePageRequest(into: &writer)
        var answer = crest_buffer_t()
        let status = writer.bytes.withUnsafeBufferPointer { bytes in
            send(table.context, bytes.baseAddress, bytes.count, &answer)
        }
        defer { release(table.context, &answer) }
        guard status == CREST_OK else {
            preconditionFailure("The engine binding refused \(type(of: request)) (\(status)). Rebuild the engine.")
        }
        var reader = WireReader(answer.bytes.map { Array(UnsafeBufferPointer(start: $0, count: answer.length)) } ?? [])
        do {
            let value = try Request.decodeAnswer(from: &reader)
            try reader.finish()
            return value
        } catch {
            preconditionFailure(
                "The engine's answer to \(type(of: request)) does not decode (\(error)). Rebuild the engine.")
        }
    }

    // MARK: - Actions - Presentations

    fileprivate func receive(_ bytes: [UInt8]) {
        var reader = WireReader(bytes)
        let presentation: EnginePresentation
        do {
            presentation = try EnginePresentation(from: &reader)
            try reader.finish()
        } catch {
            preconditionFailure("The engine's presentation does not decode (\(error)). Rebuild the engine.")
        }
        present(presentation)
    }
}

/// The binding's presentation callback. The binding presents on the thread
/// that makes requests, which is the main thread, never on a request's stack.
private func receiveEnginePresentation(_ ui: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int) {
    guard let ui else { return }
    let pages = Unmanaged<NativeEnginePages>.fromOpaque(ui).takeUnretainedValue()
    let message = bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? []
    MainActor.assumeIsolated { pages.receive(message) }
}
