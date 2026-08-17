import SwiftUI

/// Presentation vocabulary owned by the adaptive mobile sidebar shell.

enum MobileBrowserSidebarBottomChromeContent: Equatable {
    case actions
    case reservedSpace
}

enum MobileBrowserSidebarBottomChromePlacement: Equatable {
    case hidden
    case inlineSafeAreaInset
}

enum MobileBrowserSidebarMode: Equatable {
    case compactTabViewer
    case regularSidebar
}

struct MobileBrowserSidebarSpaceSheet: Equatable, Identifiable {
    let surface: BrowserUtilitySurface
    let assignment: BrowserSpaceRuntimeAssignment

    var id: String {
        let surfaceName =
            switch surface {
            case .archive: "archive"
            case .history: "history"
            case .downloads: "downloads"
            }
        return "\(surfaceName)-\(assignment.spaceID)-\(assignment.profileID.uuidString)"
    }
}
