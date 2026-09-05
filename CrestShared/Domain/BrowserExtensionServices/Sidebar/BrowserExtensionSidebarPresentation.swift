import Foundation

struct BrowserExtensionSidebarBehavior: Codable, Equatable, Sendable {
    var openPanelOnActionClick = false
}

struct BrowserExtensionSidebarPresentation: Equatable, Sendable {
    let clientID: BrowserExtensionServiceClientID
    let options: BrowserExtensionSidebarResolvedOptions
}

struct BrowserExtensionSidebarPanel: Equatable, Sendable {
    let clientID: BrowserExtensionServiceClientID
    let spaceID: SpaceID
    let documentURL: URL?
    let path: String
    let title: String
    let icon: BrowserExtensionSidebarIcon?
    let tabID: TabID?

}

struct BrowserExtensionSidebarEvent: Equatable, Sendable {
    enum Kind: String, Sendable { case opened, closed }
    let kind: Kind
    let windowID: BrowserWindowID
    let spaceID: SpaceID
    let tabID: TabID?
    let path: String
}

enum BrowserExtensionSidebarError: Error, LocalizedError {
    case unavailable
    case noActivePanel
    case noTabSpecificPanel
    case invalidResource(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "The extension side panel is unavailable."
        case .noActivePanel: "No active side panel."
        case .noTabSpecificPanel: "No active tab-specific side panel."
        case .invalidResource(let path): "Access denied for URL \(path)"
        }
    }
}

enum BrowserExtensionSidebarResourcePolicy {
    static func documentURL(path: String, baseURL: URL) -> URL? {
        guard !path.isEmpty,
            let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
            url.scheme == baseURL.scheme, url.host == baseURL.host,
            url.port == baseURL.port, url.user == nil, url.password == nil
        else { return nil }
        return url
    }
}
