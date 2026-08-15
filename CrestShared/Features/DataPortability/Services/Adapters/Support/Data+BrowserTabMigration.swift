import Foundation

extension Data {
    func littleEndianInteger<T: FixedWidthInteger>(
        at offset: Int,
        as type: T.Type
    ) -> T? {
        guard offset >= 0, offset <= count - MemoryLayout<T>.size else { return nil }
        return withUnsafeBytes { bytes in
            T(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: T.self))
        }
    }

    func int32(at offset: Int) -> Int32? {
        littleEndianInteger(at: offset, as: Int32.self)
    }

    func int64(at offset: Int) -> Int64? {
        littleEndianInteger(at: offset, as: Int64.self)
    }
}
