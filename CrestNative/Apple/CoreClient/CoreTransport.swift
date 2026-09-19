import CrestCoreABI
import Foundation

enum CoreTransportError: Error {
    case status(Int32)
    case invalidOutput
}

/// One reader and one serialized writer. The main actor never waits for a semantic result.
final class CoreTransport: @unchecked Sendable {
    let sessionID = UUID().uuidString.lowercased()
    private let handle: UInt64
    private let writer = DispatchQueue(label: "crest.core.writer", qos: .userInitiated)
    private let reader = DispatchQueue(label: "crest.core.reader", qos: .userInitiated)
    private let pendingLock = NSLock()
    private var pendingBytes = 0
    private var sequences: [String: UInt64] = [:]
    private struct PendingMessage {
        let sender: String
        var envelope: [String: Any]
        let byteCount: Int
        var encoded: Data?
    }
    private var pending: [PendingMessage] = []
    private var retryScheduled = false
    private var stopping = false
    private var closed = false
    private let receive: @MainActor @Sendable (Data) -> Void
    private let failed: @MainActor @Sendable (String) -> Void
    private let stopped: @MainActor @Sendable () -> Void

    init(
        adapters: [Data], initialState: [String: Any]? = nil, persistsSession: Bool = false, isolationMode: String = "ephemeral",
        receive: @escaping @MainActor @Sendable (Data) -> Void,
        failed: @escaping @MainActor @Sendable (String) -> Void,
        stopped: @escaping @MainActor @Sendable () -> Void
    ) throws {
        self.receive = receive
        self.failed = failed
        self.stopped = stopped
        let config = try JSONSerialization.data(withJSONObject: [
            "sessionId": sessionID, "protocolVersion": 1, "isolationMode": isolationMode,
            "queueByteLimit": 8_388_608, "messageByteLimit": 1_048_576,
            "initialState": initialState as Any? ?? NSNull(), "persistSession": persistsSession,
        ])
        var created: UInt64 = 0
        let result = config.withUnsafeBytes { bytes -> Int32 in
            var options = crest_core_options_v1(
                struct_size: UInt32(MemoryLayout<crest_core_options_v1>.size), abi_version: 1,
                configuration_utf8: bytes.bindMemory(to: UInt8.self).baseAddress,
                configuration_length: bytes.count)
            return crest_core_create(&options, &created)
        }
        guard result == 0 else { throw CoreTransportError.status(result) }
        handle = created
        do {
            for descriptor in adapters {
                let code = descriptor.withUnsafeBytes { bytes in
                    crest_core_register_adapter(created, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
                }
                guard code == 0 else { throw CoreTransportError.status(code) }
            }
            let code = crest_core_start(created)
            guard code == 0 else { throw CoreTransportError.status(code) }
        } catch {
            _ = crest_core_destroy(created)
            throw error
        }
        reader.async { [self] in readLoop() }
    }

    @MainActor
    func post(
        type: String, payload: [String: Any], sender: String = "ui",
        cause: CoreMessage? = nil
    ) {
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let correlation = cause?.correlationId ?? UUID().uuidString.lowercased()
            let causation = cause?.id
            let accepted = pendingLock.withLock {
                if pendingBytes + body.count > 8_388_608 { return false }
                pendingBytes += body.count
                return true
            }
            guard accepted else {
                failed("Host queue is full. The command was not submitted.")
                return
            }
            writer.async { [self] in
                defer { pendingLock.withLock { pendingBytes -= body.count } }
                guard !closed, !stopping || sender != "ui" else { return }
                do {
                    let envelope: [String: Any] = [
                        "protocolVersion": 1, "sessionId": sessionID, "id": UUID().uuidString.lowercased(),
                        "correlationId": correlation, "causationId": causation as Any? ?? NSNull(),
                        "sender": sender, "recipient": "core", "sequence": String(UInt64.max),
                        "kind": sender == "ui" ? "command" : "observation", "type": type,
                        "payload": try JSONSerialization.jsonObject(with: body),
                    ]
                    let bytes = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
                    guard bytes.count <= 1_048_576, pending.reduce(0, { $0 + $1.byteCount }) + bytes.count <= 8_388_608
                    else {
                        throw CoreTransportError.invalidOutput
                    }
                    pending.append(PendingMessage(sender: sender, envelope: envelope, byteCount: bytes.count))
                    flush()
                } catch { reportFailure("Unable to encode a core message.") }
            }
        } catch { failed("Unable to encode a browser command.") }
    }
    private func flush() {
        guard !closed else { return }
        while var message = pending.first {
            // Only accepted messages consume a sender sequence. A busy retry keeps
            // exactly the same ID and bytes; rejection cannot strand later work.
            let sequence = sequences[message.sender, default: 0]
            guard sequence < UInt64.max else {
                reportFailure("Core sender sequence exhausted.")
                return
            }
            if message.encoded == nil {
                message.envelope["sequence"] = String(sequence + 1)
                message.encoded = try? JSONSerialization.data(withJSONObject: message.envelope, options: [.sortedKeys])
                pending[0] = message
            }
            guard let data = message.encoded else {
                pending.removeFirst()
                reportFailure("Unable to encode a queued core message.")
                continue
            }
            let code = data.withUnsafeBytes { bytes in
                crest_core_post(handle, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
            }
            if code == 5 {
                if !retryScheduled {
                    retryScheduled = true
                    writer.asyncAfter(deadline: .now() + .milliseconds(10)) { [self] in
                        retryScheduled = false
                        flush()
                    }
                }
                return
            }
            guard code == 0 else {
                pending.removeFirst()
                reportFailure("Core rejected \(message.envelope["type"] as? String ?? "a message") (\(code)).")
                continue
            }
            sequences[message.sender] = sequence + 1
            pending.removeFirst()
        }
        if stopping { _ = crest_core_begin_shutdown(handle) }
    }
    func shutdown() {
        writer.async { [self] in
            guard !closed else { return }
            stopping = true
            flush()
        }
    }
    func resumeAfterBlockedShutdown() {
        writer.async { [self] in stopping = false }
    }
    private func reportFailure(_ text: String) {
        DispatchQueue.main.async { [failed] in failed(text) }
    }
    private func readLoop() {
        while true {
            let code = crest_core_wait_output(handle, 30_000)
            if code == 3 { continue }
            if code == 4 { break }
            guard code == 0 else {
                reportFailure("Core output failed (\(code)).")
                return
            }
            var length = 0
            guard crest_core_read_output(handle, nil, 0, &length) == 2, length > 0, length <= 1_048_576 else {
                reportFailure("Core returned an invalid message size.")
                return
            }
            var data = Data(count: length)
            let capacity = length
            let read = data.withUnsafeMutableBytes { bytes in
                crest_core_read_output(handle, bytes.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
            }
            guard read == 0 else {
                reportFailure("Core output could not be copied.")
                return
            }
            // Keep the main-actor delivery queue bounded to one message. Native work
            // can enqueue replies without waiting for this reader.
            let delivered = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { [receive, data] in
                receive(data)
                delivered.signal()
            }
            delivered.wait()
        }
        // Serialize destruction behind the final writer call. Native AOT remains loaded until exit.
        writer.async { [self] in
            closed = true
            pending.removeAll()
            let code = crest_core_wait_stopped(handle, 1000)
            guard code == 0 else {
                reportFailure("Core did not stop.")
                return
            }
            let destroyed = crest_core_destroy(handle)
            guard destroyed == 0 else {
                reportFailure("Core still has outstanding work (\(destroyed)).")
                return
            }
            DispatchQueue.main.async { [stopped] in stopped() }
        }
    }
}

struct CoreMessage {
    let sessionId: String
    let id: String
    let correlationId: String
    let causationId: String?
    let recipient: String
    let sequence: UInt64
    let kind: String
    let type: String
    let payload: [String: Any]

    init(data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["protocolVersion"] as? Int == 1, json["sender"] as? String == "core",
            let sessionId = json["sessionId"] as? String, let id = json["id"] as? String,
            let correlationId = json["correlationId"] as? String, let recipient = json["recipient"] as? String,
            let counter = json["sequence"] as? String, let sequence = UInt64(counter),
            let kind = json["kind"] as? String, let type = json["type"] as? String,
            let payload = json["payload"] as? [String: Any]
        else { throw CoreTransportError.invalidOutput }
        self.sessionId = sessionId
        self.id = id
        self.correlationId = correlationId
        self.causationId = json["causationId"] as? String
        self.recipient = recipient
        self.sequence = sequence
        self.kind = kind
        self.type = type
        self.payload = payload
    }
}
