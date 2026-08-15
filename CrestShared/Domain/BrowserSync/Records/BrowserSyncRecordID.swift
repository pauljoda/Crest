import Foundation

struct BrowserSyncRecordID: Codable, Hashable, Sendable {
    let kind: BrowserSyncRecordKind
    let value: UUID

    init(kind: BrowserSyncRecordKind, value: UUID) {
        self.kind = kind
        self.value = value
    }

    init?(recordName: String) {
        let parts = recordName.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let kind = BrowserSyncRecordKind(rawValue: String(parts[0])),
              let value = UUID(uuidString: String(parts[1])) else { return nil }
        self.init(kind: kind, value: value)
    }

    var recordName: String {
        "\(kind.rawValue):\(value.uuidString.lowercased())"
    }
}
