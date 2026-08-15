import CoreGraphics

enum BrowserFolderRowDropPolicy {
    private static let insertionBandFraction: CGFloat = 0.25

    static func location(
        y: CGFloat,
        rowHeight: CGFloat,
        before: BrowserFolderDropLocation,
        inside: BrowserFolderDropLocation
    ) -> BrowserFolderDropLocation {
        guard rowHeight > 0 else { return inside }
        return y < rowHeight * insertionBandFraction ? before : inside
    }
}
