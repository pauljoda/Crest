import AppKit

enum BrowserExtensionPopupAnchorPolicy {
    private static let width: CGFloat = 28
    private static let height: CGFloat = 1
    private static let topLeadingFallbackOffset = CGPoint(x: 292, y: 36)

    static func anchorRect(
        in bounds: CGRect,
        interactionPoint: CGPoint?
    ) -> CGRect {
        let point =
            interactionPoint.flatMap { bounds.contains($0) ? $0 : nil }
            ?? CGPoint(
                x: min(
                    bounds.maxX - width / 2,
                    bounds.minX + topLeadingFallbackOffset.x
                ),
                y: bounds.maxY - topLeadingFallbackOffset.y
            )
        let centerX = min(
            max(point.x, bounds.minX + width / 2),
            bounds.maxX - width / 2
        )
        let centerY = min(max(point.y, bounds.minY), bounds.maxY)
        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }
}
