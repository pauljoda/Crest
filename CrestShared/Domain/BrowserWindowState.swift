import Foundation

/// A window's sidebar layout on this device: how wide the sidebar is and
/// whether it is shown. Only the platform reads it. What the window shows,
/// and its split columns, are the core's window state.
struct BrowserWindowState: Codable, Equatable, Identifiable, Sendable {
    let id: BrowserWindowID
    private(set) var sidebarWidth: Double?
    private(set) var sidebarIsPresented: Bool?

    init(id: BrowserWindowID, sidebarWidth: Double? = nil, sidebarIsPresented: Bool? = nil) {
        self.id = id
        self.sidebarWidth = sidebarWidth
        self.sidebarIsPresented = sidebarIsPresented
    }

    mutating func captureSidebar(width: Double? = nil, isPresented: Bool? = nil) {
        if let width, width.isFinite, width > 0 {
            sidebarWidth = width
        }
        if let isPresented {
            sidebarIsPresented = isPresented
        }
    }
}
