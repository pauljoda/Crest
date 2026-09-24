import CrestCoreABI
import Foundation

extension CrestCore {
    // MARK: - Actions - Engines

    /// Registers an engine with the core and answers the core's handle for it.
    /// The core runs the engine's commands through `relay` on the thread that
    /// sent the intent or report that caused them, which is the main thread.
    func registerEngine(_ registration: EngineRegistration, relay: Engines.Relay) throws(Rejection) -> UInt64 {
        var writer = WireWriter()
        registration.encode(into: &writer)
        var engine: UInt64 = 0
        var refusal = crest_buffer_t()
        var binding = crest_engine_binding_t(
            context: Unmanaged.passUnretained(relay).toOpaque(), attach: nil, run: relayEngineCommand)
        let status = CoreCodec.engineFingerprint.withUnsafeBufferPointer { fingerprint in
            writer.bytes.withUnsafeBufferPointer { settings in
                crest_engine_register(
                    handle, fingerprint.baseAddress, fingerprint.count, settings.baseAddress, settings.count, &binding,
                    &engine, &refusal)
            }
        }
        defer { crest_buffer_free(&refusal) }
        switch status {
        case CREST_OK:
            return engine
        case CREST_REJECTED:
            throw Self.rejection(in: refusal)
        default:
            Self.buildBug(status, "register an engine")
        }
    }

    /// Reports what happened to one of an engine's pages. What it changed
    /// arrives with the next drain.
    func report(_ event: some EngineEvent, engine: UInt64) {
        var writer = WireWriter()
        event.encodeEngineEvent(into: &writer)
        let status = writer.bytes.withUnsafeBufferPointer {
            crest_engine_report(handle, engine, $0.baseAddress, $0.count)
        }
        guard status == CREST_OK else { Self.buildBug(status, "take \(type(of: event)) from an engine") }
    }
}

/// The core's command callback. It runs on the main thread, which sends every
/// intent and report, outside every core lock.
private func relayEngineCommand(_ context: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int) {
    guard let context else { return }
    let relay = Unmanaged<Engines.Relay>.fromOpaque(context).takeUnretainedValue()
    var reader = WireReader(bytes.map { Array(UnsafeBufferPointer(start: $0, count: length)) } ?? [])
    let command: EngineCommand
    do {
        command = try EngineCommand(from: &reader)
        try reader.finish()
    } catch {
        preconditionFailure("The core's engine command does not decode (\(error)). Rebuild the core.")
    }
    MainActor.assumeIsolated { relay.engines?.run(command, on: relay.kind) }
}
