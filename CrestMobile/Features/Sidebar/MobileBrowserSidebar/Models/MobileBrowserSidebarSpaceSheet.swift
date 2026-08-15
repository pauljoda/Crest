import Foundation

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
