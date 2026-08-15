import Foundation

enum ChromiumTabSessionAdapter {
    private static let header = Data("SNSS".utf8)

    static func decode(
        _ data: Data,
        importedAt: Date
    ) throws -> [BrowserTabSessionDraft] {
        guard data.count >= 8, data.starts(with: header),
            let version = data.littleEndianInteger(at: 4, as: UInt32.self)
        else {
            throw BrowserTabMigrationError.invalidContents
        }
        if version == 5 {
            throw BrowserTabMigrationError.encryptedChromiumSession
        }
        guard version == 3 else {
            throw BrowserTabMigrationError.invalidContents
        }
        var state = ChromiumSessionState(importedAt: importedAt)
        var position = 8
        while position < data.count {
            guard
                let sizeValue = data.littleEndianInteger(
                    at: position,
                    as: UInt16.self
                )
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            let size = Int(sizeValue)
            guard size >= 1,
                size <= data.count - position - 2
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            let commandID = data[position + 2]
            let payloadStart = position + 3
            let payloadEnd = position + 2 + size
            try state.apply(
                commandID: commandID,
                payload: data.subdata(in: payloadStart..<payloadEnd)
            )
            position = payloadEnd
        }
        guard position == data.count, state.hasInitialStateMarker else {
            throw BrowserTabMigrationError.invalidContents
        }
        return state.drafts()
    }
}
