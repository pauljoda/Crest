import SwiftUI

/// Lets the desktop shell consume a completed lift outside its source window.
/// In-window reordering and mobile input keep using the shared reorder path.
struct BrowserSidebarWindowDrop {
    var perform: @MainActor (BrowserSidebarReorderItem) -> Bool
}

extension EnvironmentValues {
    @Entry var browserSidebarWindowDrop: BrowserSidebarWindowDrop? = nil
}
