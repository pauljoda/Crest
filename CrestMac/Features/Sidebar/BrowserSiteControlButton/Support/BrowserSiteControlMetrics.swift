import CoreGraphics

/// The geometry of the Site Controls trigger and of the extension tiles an
/// engine adds to Site Controls.
enum BrowserSiteControlMetrics {
    static let extensionActionHeight: CGFloat = 34
    static let extensionGlyphSize: CGFloat = 17
    static let extensionColumnCount = 4
    static let extensionGridSpacing: CGFloat = 6
    static let triggerSize = CGSize(
        width: BrowserTabTrailingControlMetrics.pointer.controlSize.height,
        height: BrowserTabTrailingControlMetrics.pointer.controlSize.height
    )
}
