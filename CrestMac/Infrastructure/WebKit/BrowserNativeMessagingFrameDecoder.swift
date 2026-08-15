import Foundation
import WebKit

struct BrowserNativeMessagingFrameDecoder {
    private var buffer = Data()

    /// Consumes a stream chunk and returns every complete frame it completes.
    ///
    /// `Data` indices are absolute, not count-relative: consuming bytes with
    /// `removeFirst` advances `startIndex` without rebasing it, and appending
    /// more bytes does not rebase it either. A literal `buffer[4..<total]`
    /// therefore traps as soon as one frame has been consumed, so every index
    /// below is derived from `buffer.startIndex` and each consumed frame
    /// rebases the buffer.
    mutating func append<D: DataProtocol>(_ data: D) throws -> [Any] {
        buffer.append(contentsOf: data)
        var messages: [Any] = []
        let headerLength = MemoryLayout<UInt32>.size
        while buffer.count >= headerLength {
            let payloadStart = buffer.startIndex + headerLength
            let length = buffer[buffer.startIndex..<payloadStart].withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
            }
            guard
                length
                    <= BrowserNativeMessagingFrameCodec
                    .maximumHostMessageSize
            else {
                throw BrowserNativeMessagingHostError.messageTooLarge
            }
            guard buffer.count >= headerLength + Int(length) else { break }
            let payloadEnd = payloadStart + Int(length)
            let value = try JSONSerialization.jsonObject(
                with: buffer[payloadStart..<payloadEnd],
                options: .fragmentsAllowed
            )
            messages.append(value)
            buffer = Data(buffer[payloadEnd...])
        }
        return messages
    }
}
