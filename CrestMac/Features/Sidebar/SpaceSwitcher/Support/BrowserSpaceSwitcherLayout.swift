import CoreGraphics

enum BrowserSpaceSwitcherLayout {
    static let usesOneButtonPerSpace = true
    static let leadingUtility: BrowserSpaceSwitcherUtility? = nil
    static let trailingUtility = BrowserSpaceSwitcherUtility.commonLists
    static let showsSpaceCreation = false
    static let segmentWidth = CrestSpaceIconPickerMetrics.segmentWidth
    static let segmentHeight = CrestSpaceIconPickerMetrics.segmentHeight
    static let cornerRadius = CrestSpaceIconPickerMetrics.cornerRadius

    static func segmentIDs(for spaces: [BrowserSpace]) -> [SpaceID] {
        spaces.map(\.id)
    }
}
