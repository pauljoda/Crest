import Foundation

enum BrowserSyncPayload: Codable, Equatable, Sendable {
    case space(BrowserSyncSpace)
    case folder(BrowserSyncFolder)
    case tab(BrowserSyncTab)
    case history(BrowserSyncHistory)
    case archive(BrowserSyncArchive)

    var recordID: BrowserSyncRecordID {
        switch self {
        case let .space(space):
            BrowserSyncRecordID(kind: .space, value: space.id.rawValue)
        case let .folder(folder):
            BrowserSyncRecordID(kind: .folder, value: folder.id.rawValue)
        case let .tab(tab):
            BrowserSyncRecordID(kind: .tab, value: tab.id.rawValue)
        case let .history(history):
            BrowserSyncRecordID(kind: .history, value: history.id)
        case let .archive(archive):
            BrowserSyncRecordID(kind: .archive, value: archive.id.rawValue)
        }
    }

    var spaceID: SpaceID {
        switch self {
        case let .space(space): space.id
        case let .folder(folder): folder.spaceID
        case let .tab(tab): tab.spaceID
        case let .history(history): history.spaceID
        case let .archive(archive): archive.spaceID
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BrowserSyncRecordKind.self, forKey: .type)
        switch type {
        case .space:
            self = .space(try container.decode(BrowserSyncSpace.self, forKey: .value))
        case .folder:
            self = .folder(try container.decode(BrowserSyncFolder.self, forKey: .value))
        case .tab:
            self = .tab(try container.decode(BrowserSyncTab.self, forKey: .value))
        case .history:
            self = .history(try container.decode(BrowserSyncHistory.self, forKey: .value))
        case .archive:
            self = .archive(try container.decode(BrowserSyncArchive.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .space(value):
            try container.encode(BrowserSyncRecordKind.space, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .folder(value):
            try container.encode(BrowserSyncRecordKind.folder, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .tab(value):
            try container.encode(BrowserSyncRecordKind.tab, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .history(value):
            try container.encode(BrowserSyncRecordKind.history, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .archive(value):
            try container.encode(BrowserSyncRecordKind.archive, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}
