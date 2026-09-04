import Foundation

/// Session-local browser identity, independent of the extension using a group.
struct BrowserExtensionTabGroupID: Hashable, Sendable {
    let rawValue: Int
}

enum BrowserExtensionTabGroupColor: String, CaseIterable, Sendable {
    case grey, blue, red, yellow, green, pink, purple, cyan, orange
}

struct BrowserExtensionTabGroup: Equatable, Sendable {
    let id: BrowserExtensionTabGroupID
    let spaceID: SpaceID
    var tabs: [TabID]
    var title: String?
    var color: BrowserExtensionTabGroupColor = .grey
    var isCollapsed = false
}

enum BrowserExtensionTabGroupError: Error, Equatable {
    case emptyTabList
    case unknownGroup(BrowserExtensionTabGroupID)
}
