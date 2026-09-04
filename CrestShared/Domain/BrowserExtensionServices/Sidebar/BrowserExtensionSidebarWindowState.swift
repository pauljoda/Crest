import Foundation

/// Device-local preferences, deliberately excluding whether a panel is open.
struct BrowserExtensionSidebarWindowState: Codable, Equatable, Sendable {
    var lastClientID: BrowserExtensionServiceClientID?
    var width: Double?
}
