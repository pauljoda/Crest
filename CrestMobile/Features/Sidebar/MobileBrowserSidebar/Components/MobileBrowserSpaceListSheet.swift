import SwiftUI

/// One of a Space's lists — its archive, history or downloads — shown as a
/// sheet. The docked sidebar puts its lists up this way, and so does a narrow
/// window when a command asks for one while that sidebar is the tab viewer.
struct MobileBrowserSpaceListSheet: View {
    let request: MobileBrowserSidebarSpaceSheet
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let selectTab: (UUID) -> Void
    let openURL: (URL) -> Void

    var body: some View {
        switch request.surface.kind {
        case .archive:
            MobileArchiveView(
                browser: browser,
                assignment: request.assignment,
                spaceAccess: spaceAccess,
                selectTab: selectTab
            )
        case .history:
            MobileHistoryView(
                browser: browser,
                assignment: request.assignment,
                spaceAccess: spaceAccess,
                openURL: openURL
            )
        case .downloads:
            MobileDownloadsView(
                browser: browser,
                pages: pages,
                assignment: request.assignment,
                spaceAccess: spaceAccess
            )
        }
    }
}
