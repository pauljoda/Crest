import CryptoKit
import Foundation

/// One bounded byte transfer. Reference ownership avoids copying the accumulated
/// buffer on every frame. Neither UI nor persistence sees partially assembled data.
final class CoreChunkTransfer {
    let begin: CoreMessage
    private let byteCount: Int
    private let chunkCount: Int
    private let digest: String
    private let identityKey: String
    private var nextIndex = 0
    private var bytes = Data()
    private var failed: Bool

    init(begin: CoreMessage, identityKey: String, byteLimit: Int = 16_000_000) throws {
        guard let byteCount = begin.payload["byteCount"] as? Int,
            let chunkCount = begin.payload["chunkCount"] as? Int,
            let digest = begin.payload["sha256"] as? String,
            byteCount > 0, chunkCount > 0, digest.count == 64
        else { throw CoreTransportError.invalidOutput }
        self.begin = begin; self.identityKey = identityKey
        self.byteCount = byteCount; self.chunkCount = chunkCount; self.digest = digest
        failed = byteCount > byteLimit || chunkCount > 8192
        if !failed { bytes.reserveCapacity(byteCount) }
    }
    private func validate(_ message: CoreMessage) throws {
        guard message.payload[identityKey] as? String == begin.id, message.causationId == begin.id,
            message.sessionId == begin.sessionId, message.correlationId == begin.correlationId,
            message.payload["revision"] as? String == begin.payload["revision"] as? String
        else { throw CoreTransportError.invalidOutput }
    }
    func append(_ message: CoreMessage) throws {
        try validate(message)
        guard !failed else { return }
        guard let index = message.payload["index"] as? Int, index == nextIndex, index < chunkCount,
            let encoded = message.payload["data"] as? String, let chunk = Data(base64Encoded: encoded),
            chunk.count <= 65536, bytes.count + chunk.count <= byteCount else {
            failed = true; bytes.removeAll(); return
        }
        bytes.append(chunk); nextIndex += 1
    }
    func finish(_ message: CoreMessage) throws -> Data {
        try validate(message)
        guard !failed, nextIndex == chunkCount, bytes.count == byteCount,
            SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == digest
        else { throw CoreTransportError.invalidOutput }
        return bytes
    }
}
