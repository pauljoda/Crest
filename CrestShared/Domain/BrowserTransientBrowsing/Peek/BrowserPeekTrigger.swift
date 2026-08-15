import Foundation

enum BrowserPeekTrigger: String, Codable, Equatable, Sendable {
    case protectedSavedSite
    case modifierClick
    case longPress
}
