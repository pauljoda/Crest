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

struct MobileBrowserSidebarSpaceSheet: Equatable, Identifiable {
    let surface: BrowserUtilitySurface
    let assignment: BrowserSpaceRuntimeAssignment

    var id: String {
        "\(surface.name)-\(assignment.spaceID)-\(assignment.profileID.uuidString)"
    }
}
