import Foundation

struct TabID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
