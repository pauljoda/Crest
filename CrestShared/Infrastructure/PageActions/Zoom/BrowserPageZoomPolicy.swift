import CoreGraphics

/// Forwarders kept only for CrestMobile, which another batch owns. Delete this
/// file once `MobileBrowserPage` and the mobile page actions read the zoom
/// rules from `CGFloat` and `BrowserDefaultPageZoomStore` directly.
enum BrowserPageZoomPolicy {
    static let defaultLevel = BrowserDefaultPageZoomStore.defaultLevel

    static func increased(from current: CGFloat) -> CGFloat { current.pageZoomIncreased }

    static func decreased(from current: CGFloat) -> CGFloat { current.pageZoomDecreased }

    static func percentageLabel(for zoom: CGFloat) -> String { zoom.pageZoomPercentage }

    static func normalizedDefault(_ proposed: CGFloat) -> CGFloat { BrowserDefaultPageZoomStore.normalized(proposed) }

    static func levelsMatch(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool { lhs.matchesPageZoom(rhs) }
}
