import CoreGraphics
import Foundation

enum BrowserQuickWindowLayout {
    static let defaultWidth: CGFloat = 720
    static let defaultHeight: CGFloat = 460
    static let minimumWidth: CGFloat = 600
    static let minimumHeight: CGFloat = 400
    static let toolbarHeight: CGFloat = 56
    static let controlHeight: CGFloat = BrowserChromeLayout.addressHeight
    static let minimumMacHitTarget: CGFloat = 28
    static let addressMinimumWidth: CGFloat = 220
    static let addressVerticalPadding: CGFloat = 6
    static let pageTopClearance: CGFloat = 6
    static let horizontalPadding: CGFloat = 10
    static let toolbarVerticalPadding: CGFloat = horizontalPadding
    static let pageFrameInset: CGFloat = BrowserChromeLayout.pageFrameInset
    static let pageBrandSeamWidth: CGFloat = BrowserChromeLayout.pageBrandSeamWidth
    static let pageCornerRadius: CGFloat = BrowserChromeLayout.pageCornerRadius
    static let pageContentCornerRadius: CGFloat = BrowserChromeLayout.pageContentCornerRadius
    static let toolbarSpacing: CGFloat = 8
    static let sourceChipHorizontalPadding: CGFloat = 9
    static let windowControlClearance: CGFloat = 92
    static let spacePickerWidth: CGFloat = 240
    static let spacePickerRowHeight: CGFloat = 38
    static let initialAddressFocusDelay: Duration = .milliseconds(120)
}
