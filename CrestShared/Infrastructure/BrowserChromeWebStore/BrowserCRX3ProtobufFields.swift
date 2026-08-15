import Foundation

struct BrowserCRX3ProtobufFields {
    private var lengthDelimited: [Int: [Data]] = [:]

    init(data: Data) throws {
        var offset = 0
        while offset < data.count {
            let key = try Self.readVarint(data, offset: &offset)
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x07)
            guard fieldNumber > 0 else {
                throw BrowserCRX3VerifierError.invalidHeader
            }
            switch wireType {
            case 0:
                _ = try Self.readVarint(data, offset: &offset)
            case 1:
                try Self.advance(8, in: data, offset: &offset)
            case 2:
                let length = try Self.readVarint(data, offset: &offset)
                guard length <= UInt64(Int.max) else {
                    throw BrowserCRX3VerifierError.invalidHeader
                }
                let byteCount = Int(length)
                guard byteCount <= data.count - offset else {
                    throw BrowserCRX3VerifierError.invalidHeader
                }
                lengthDelimited[fieldNumber, default: []].append(
                    Data(data[offset..<offset + byteCount])
                )
                offset += byteCount
            case 5:
                try Self.advance(4, in: data, offset: &offset)
            default:
                throw BrowserCRX3VerifierError.invalidHeader
            }
        }
    }

    func lengthDelimitedValues(for field: Int) -> [Data] {
        lengthDelimited[field] ?? []
    }

    private static func readVarint(
        _ data: Data,
        offset: inout Int
    ) throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard offset < data.count else {
                throw BrowserCRX3VerifierError.invalidHeader
            }
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << UInt64(shift)
            if byte & 0x80 == 0 { return result }
        }
        throw BrowserCRX3VerifierError.invalidHeader
    }

    private static func advance(
        _ byteCount: Int,
        in data: Data,
        offset: inout Int
    ) throws {
        guard byteCount <= data.count - offset else {
            throw BrowserCRX3VerifierError.invalidHeader
        }
        offset += byteCount
    }
}
