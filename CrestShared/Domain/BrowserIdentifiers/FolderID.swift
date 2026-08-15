import Foundation

struct FolderID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
