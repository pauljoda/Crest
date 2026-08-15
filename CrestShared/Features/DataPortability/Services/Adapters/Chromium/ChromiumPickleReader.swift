import Foundation

struct ChromiumPickleReader {
    private let data: Data
    private let end: Int
    private var position = 4

    init(_ data: Data) throws {
        guard let declaredSize = data.littleEndianInteger(at: 0, as: UInt32.self),
            declaredSize <= data.count - 4
        else {
            throw BrowserTabMigrationError.invalidContents
        }
        self.data = data
        end = 4 + Int(declaredSize)
    }

    mutating func readInt32() -> Int32? {
        guard let value = data.littleEndianInteger(at: position, as: Int32.self),
            position + 4 <= end
        else { return nil }
        position += 4
        return value
    }

    mutating func readString(maximumByteCount: Int) -> String? {
        guard let lengthValue = readInt32(), lengthValue >= 0 else { return nil }
        let length = Int(lengthValue)
        guard length <= maximumByteCount,
            length <= end - position
        else { return nil }
        let value = String(
            decoding: data[position..<(position + length)],
            as: UTF8.self
        )
        position += length
        return alignAndReturn(value)
    }

    mutating func readString16(maximumCodeUnitCount: Int) -> String? {
        guard let lengthValue = readInt32(), lengthValue >= 0 else { return nil }
        let count = Int(lengthValue)
        let byteCount = count.multipliedReportingOverflow(by: 2)
        guard !byteCount.overflow,
            count <= maximumCodeUnitCount,
            byteCount.partialValue <= end - position
        else { return nil }
        var units: [UInt16] = []
        units.reserveCapacity(count)
        for offset in stride(from: position, to: position + byteCount.partialValue, by: 2) {
            guard let unit = data.littleEndianInteger(at: offset, as: UInt16.self) else {
                return nil
            }
            units.append(unit)
        }
        position += byteCount.partialValue
        return alignAndReturn(String(decoding: units, as: UTF16.self))
    }

    private mutating func alignAndReturn(_ value: String) -> String? {
        position = (position + 3) & ~3
        guard position <= end else { return nil }
        return value
    }
}
