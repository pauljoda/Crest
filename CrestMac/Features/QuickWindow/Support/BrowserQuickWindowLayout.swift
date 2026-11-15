import CoreGraphics
import Foundation

enum BrowserQuickWindowLayout {
    static let defaultWidth: CGFloat = 720
    static let defaultHeight: CGFloat = 460
    static let minimumWidth: CGFloat = 600
    static let minimumHeight: CGFloat = 400
    static let maximumScreenFallbackWidth: CGFloat = 1_440
    static let maximumScreenFallbackHeight: CGFloat = 1_000
    /// How far a Quick Window opening where another already is moves down and
    /// to the right, and how many such steps it takes at most.
    static let cascadeStep: CGFloat = 22
    static let cascadeLimit = 8
    /// The smallest window in another app a Quick Window opens over, which
    /// leaves out palettes and the invisible windows some apps keep on screen.
    static let minimumForeignWindowSize: CGFloat = 160
    // The page surface owns the gap below the controls through its frame inset.
    static let toolbarHeight: CGFloat = BrowserPageBarMetrics.quickWindow.height
    static let controlHeight: CGFloat = BrowserPageBarMetrics.quickWindow.fieldHeight
    static let minimumMacHitTarget: CGFloat = 28
    static let addressMinimumWidth: CGFloat = BrowserPageBarMetrics.quickWindow.fieldMinimumWidth
    static let addressVerticalPadding: CGFloat = 6
    static let horizontalPadding: CGFloat = BrowserPageBarMetrics.quickWindow.trailingPadding
    /// Where the window's traffic lights are centred, from its top: the
    /// toolbar's controls share their centre line.
    static let windowControlsCenterY: CGFloat = BrowserPageBarMetrics.windowControlsCenterY
    static let toolbarTopPadding: CGFloat = BrowserPageBarMetrics.quickWindow.topPadding
    /// Reload, its menu and Site Controls at the field's end sit close
    /// together, each as wide as its glyph needs.
    static let trailingControlSpacing: CGFloat = 2
    static let reloadControlSize = BrowserPageBarMetrics.reloadControlSize
    static let reloadMenuControlSize = BrowserPageBarMetrics.reloadMenuControlSize
    static let sourceChipLeadingInset: CGFloat = (controlHeight - CrestLayout.minimumHitTarget) / 2
    static let windowControlClearance: CGFloat = BrowserPageBarMetrics.windowControlsClearance
    static let spacePickerWidth: CGFloat = 240
    static let spacePickerRowHeight: CGFloat = 38
    static let initialAddressFocusDelay: Duration = .milliseconds(120)
}
