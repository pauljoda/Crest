import Foundation

/// Session-local browser identity, independent of the extension using a group.
struct BrowserExtensionTabGroupID: Codable, Hashable, Sendable {
    let rawValue: Int
}

enum BrowserExtensionTabGroupColor: String, Codable, CaseIterable, Sendable {
    case grey, blue, red, yellow, green, pink, purple, cyan, orange

    static func nearest(to color: BrowserSpaceBrandColor) -> Self {
        func distance(_ value: Self) -> Double {
            let other = value.brandColor
            return pow(color.red - other.red, 2) + pow(color.green - other.green, 2) + pow(color.blue - other.blue, 2)
        }
        return allCases.min { distance($0) < distance($1) } ?? .grey
    }

    /// Shared by open and saved folders, so promotion preserves the visible color.
    var brandColor: BrowserSpaceBrandColor {
        switch self {
        case .grey: .init(red: 0.56, green: 0.56, blue: 0.58)
        case .blue: .init(red: 0.04, green: 0.52, blue: 1)
        case .red: .init(red: 1, green: 0.27, blue: 0.23)
        case .yellow: .init(red: 1, green: 0.84, blue: 0.04)
        case .green: .init(red: 0.19, green: 0.82, blue: 0.35)
        case .pink: .init(red: 1, green: 0.22, blue: 0.37)
        case .purple: .init(red: 0.75, green: 0.35, blue: 0.95)
        case .cyan: .init(red: 0.39, green: 0.82, blue: 1)
        case .orange: .init(red: 1, green: 0.62, blue: 0.04)
        }
    }
}

struct BrowserExtensionTabGroup: Codable, Equatable, Sendable {
    let id: BrowserExtensionTabGroupID
    var folderID = FolderID()
    let spaceID: SpaceID
    var tabs: [TabID]
    var title: String?
    var color: BrowserExtensionTabGroupColor = .grey
    var isCollapsed = false

}

enum BrowserExtensionTabGroupError: Error, Equatable {
    case emptyTabList
    case unknownGroup(BrowserExtensionTabGroupID)
    case unavailableTab(TabID)
}
