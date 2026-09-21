import Foundation

enum BrowserPeekTrigger: String, Codable, Equatable, Sendable {
    case protectedSavedSite
    case modifierClick
    case linkDrag
    case longPress
    case contextMenu
}
