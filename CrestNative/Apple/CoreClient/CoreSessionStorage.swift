import Darwin
import Foundation

/// A byte-storage port. The core owns decoding, migration, and every semantic mutation.
/// This target's container and lock are separate from the installed Crest application.
final class CoreSessionStorage: @unchecked Sendable {
    private let directory: URL
    private let file: URL
    private let lockFile: Int32
    private let queue = DispatchQueue(label: "crest.core.session-storage", qos: .utility)
    @MainActor private var transfer: CoreChunkTransfer?

    init(directory suppliedDirectory: URL? = nil) throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = suppliedDirectory ?? support.appendingPathComponent("CrestControlPlane", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("session.json")
        lockFile = Darwin.open(directory.appendingPathComponent("session.lock").path, O_RDWR | O_CREAT, 0o600)
        guard lockFile >= 0 else { throw CocoaError(.fileWriteUnknown) }
        guard flock(lockFile, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lockFile)
            throw CocoaError(.fileLocking)
        }
    }
    deinit { flock(lockFile, LOCK_UN); Darwin.close(lockFile) }

    func load() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let bytes = try Data(contentsOf: file)
        guard bytes.count <= 16_000_000,
            let state = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
            state["formatVersion"] as? Int == 1
        else { throw CocoaError(.fileReadCorruptFile) }
        return state
    }

    @MainActor
    func save(_ message: CoreMessage, completion: @escaping @MainActor @Sendable (CoreMessage, Bool) -> Void) {
        do {
            if message.type == "services.session_begin" {
                guard transfer == nil else { throw CoreTransportError.invalidOutput }
                transfer = try CoreChunkTransfer(begin: message, identityKey: "saveId")
                return
            }
            if message.type == "services.session_chunk" {
                guard let transfer else { throw CoreTransportError.invalidOutput }
                try transfer.append(message)
                return
            }
            if message.type == "services.session_commit" {
                guard let incoming = transfer else { throw CoreTransportError.invalidOutput }
                let bytes = try incoming.finish(message)
                transfer = nil
                write(bytes) { completion(incoming.begin, $0) }
                return
            }
            guard transfer == nil, message.type == "services.save_session", let state = message.payload["state"] as? [String: Any] else {
                throw CoreTransportError.invalidOutput
            }
            let bytes = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
            guard bytes.count <= 16_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
            write(bytes) { completion(message, $0) }
        } catch {
            // Every transfer has one terminal acknowledgement, addressed to its
            // begin effect even when a later frame violates the contract.
            let failed = transfer?.begin ?? message
            transfer = nil
            completion(failed, false)
        }
    }
    private func write(_ bytes: Data, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        queue.async { [self] in
            let succeeded: Bool
            do {
                try bytes.write(to: file, options: .atomic)
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.synchronize()
                let descriptor = Darwin.open(directory.path, O_RDONLY)
                guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
                defer { Darwin.close(descriptor) }
                guard fsync(descriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
                succeeded = true
            } catch { succeeded = false }
            DispatchQueue.main.async { completion(succeeded) }
        }
    }
}
