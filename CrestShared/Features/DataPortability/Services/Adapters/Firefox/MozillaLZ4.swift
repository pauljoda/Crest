import Compression
import Foundation

enum MozillaLZ4 {
    private static let magic = Data("mozLz40\0".utf8)

    static func decompressedData(_ data: Data) throws -> Data {
        guard data.starts(with: magic) else {
            guard data.count <= BrowserTabMigration.maximumDecodedByteCount else {
                throw BrowserTabMigrationError.resourceLimitExceeded
            }
            return data
        }
        guard data.count > 12,
            let decodedByteCount = data.littleEndianInteger(
                at: 8,
                as: UInt32.self
            ).map(Int.init),
            decodedByteCount > 0,
            decodedByteCount <= BrowserTabMigration.maximumDecodedByteCount
        else {
            throw BrowserTabMigrationError.resourceLimitExceeded
        }
        let compressed = data.subdata(in: 12..<data.count)
        var decoded = Data(count: decodedByteCount)
        let result = decoded.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                guard
                    let destinationAddress =
                        destination
                        .bindMemory(to: UInt8.self)
                        .baseAddress,
                    let sourceAddress =
                        source
                        .bindMemory(to: UInt8.self)
                        .baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    destinationAddress,
                    decodedByteCount,
                    sourceAddress,
                    compressed.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }
        guard result == decodedByteCount else {
            throw BrowserTabMigrationError.invalidContents
        }
        return decoded
    }
}
