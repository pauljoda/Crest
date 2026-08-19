import CoreGraphics

/// The pointer shell's trailing-control geometry, named where its call sites
/// already reach for it.
///
/// The numbers themselves belong to `BrowserTabTrailingControlMetrics.pointer`
/// — one definition the touch profile can be compared against — and this stays
/// as the spelling the macOS sidebar rows use.
enum BrowserTabTrailingControlPolicy {
    private static let metrics = BrowserTabTrailingControlMetrics.pointer

    static let minimumHitTarget = metrics.controlSize.height
    static let glyphSize = metrics.glyphSize
    static let size = metrics.controlSize
}
