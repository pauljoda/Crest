import CoreGraphics

enum BrowserSidebarScrollLayoutPolicy {
    static let clipsScrollableRegion = true
    static let fixedSpaceHeaderMaxHeight: CGFloat? = nil

    static func region(
        for section: BrowserSidebarSection
    ) -> BrowserSidebarScrollRegion {
        switch section {
        case .essentials, .spaceIdentity:
            .fixed
        case .savedTabs, .currentTabs:
            .scrollable
        }
    }
}
