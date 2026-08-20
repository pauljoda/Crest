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

/// Where the archive, history, and downloads lists come up.
///
/// A sidebar standing beside a page has room to swap its own body for the list
/// and keeps the reader in place. A sidebar that *is* the screen has nowhere to
/// put a list except over itself, so it presents a sheet and leaves its tabs
/// underneath. This is the choice each placement makes, not a device: the same
/// build makes it both ways in one session.
enum MobileBrowserSidebarUtilityPresentationStyle: Equatable {
    case inline
    case sheet
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
