import Foundation

struct BrowserWindowID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    /// The one regular browser shell shared by every non-private Space.
    static let main = BrowserWindowID(
        // 3A92C7E8-46F1-4D55-86BB-0F226747F8D1
        rawValue: UUID(
            uuid: (
                0x3A, 0x92, 0xC7, 0xE8,
                0x46, 0xF1,
                0x4D, 0x55,
                0x86, 0xBB,
                0x0F, 0x22, 0x67, 0x47, 0xF8, 0xD1
            ))
    )
}

struct FolderID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct SpaceID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct SplitGroupID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct TabID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
