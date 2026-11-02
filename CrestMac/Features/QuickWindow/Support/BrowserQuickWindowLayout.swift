import CoreGraphics
import Foundation

enum BrowserQuickWindowLayout {
    static let defaultWidth: CGFloat = 720
    static let defaultHeight: CGFloat = 460
    static let minimumWidth: CGFloat = 600
    static let minimumHeight: CGFloat = 400
    static let maximumScreenFallbackWidth: CGFloat = 1_440
    static let maximumScreenFallbackHeight: CGFloat = 1_000
    // The page surface owns the gap below the controls through its frame inset.
    static let toolbarHeight: CGFloat = controlHeight + toolbarTopPadding
    static let controlHeight: CGFloat = BrowserChromeLayout.addressHeight
    static let minimumMacHitTarget: CGFloat = 28
    static let addressMinimumWidth: CGFloat = 220
    /// The width the address field keeps before pinned extensions show
    /// beside it, so its address stays readable at the window's smallest.
    static let addressWidthBeforeExtensions: CGFloat = 300
    static let addressVerticalPadding: CGFloat = 6
    static let horizontalPadding: CGFloat = 10
    /// Where the window's traffic lights are centred, from its top: the
    /// toolbar's controls share their centre line.
    static let windowControlsCenterY: CGFloat = 26
    static let toolbarTopPadding: CGFloat = windowControlsCenterY - controlHeight / 2
    static let toolbarSpacing: CGFloat = 8
    static let sourceChipHorizontalPadding: CGFloat = 9
    static let sourceChipLeadingInset: CGFloat = (controlHeight - CrestLayout.minimumHitTarget) / 2
    static let windowControlClearance: CGFloat = 92
    static let spacePickerWidth: CGFloat = 240
    static let spacePickerRowHeight: CGFloat = 38
    static let initialAddressFocusDelay: Duration = .milliseconds(120)
}
