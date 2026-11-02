import SwiftUI

/// Where the Close and Open In controls are shown: the action bar beside a
/// Peek's card, or a Quick Window's toolbar. Each place sets the controls'
/// height, the size of the Space's icon in them, and their shape.
struct BrowserPeekControlStyle: Hashable, Sendable {
    // MARK: - Static Variables

    /// Floating pills beside a Peek's card, Open In taking the bar's width.
    static let actionBar = BrowserPeekControlStyle(
        height: 48, iconSize: 22, leadingInset: 16, menuWidth: 48, spaceNameWidth: nil, fillsWidth: true,
        followsChromeCorners: false)
    /// Controls in a Quick Window's toolbar, shaped like its address field.
    static let toolbar = BrowserPeekControlStyle(
        height: BrowserChromeLayout.addressHeight, iconSize: 18, leadingInset: 10, menuWidth: 30, spaceNameWidth: 118,
        fillsWidth: false, followsChromeCorners: true)

    // MARK: - Variables

    let height: CGFloat
    let iconSize: CGFloat
    /// The space before the Space's icon in Open In.
    let leadingInset: CGFloat
    /// The width of Open In's menu of other Spaces.
    let menuWidth: CGFloat
    /// The widest Open In's title may grow when it names the Space, about
    /// eight characters of the name, or nil where it reads "Open In…". A
    /// shorter name keeps a shorter title.
    let spaceNameWidth: CGFloat?
    /// Whether Open In takes the width its place gives it rather than its
    /// own.
    let fillsWidth: Bool
    /// Whether the controls on the Mac wear the chrome's corner radius, as
    /// the address field beside them does, rather than a pill's.
    let followsChromeCorners: Bool

    /// The controls' shape: the corner radius the person chose in Look and
    /// Feel where they sit in the Mac's chrome, else a capsule, as a Peek's
    /// floating controls and every control under a thumb are. Read in a
    /// view's body, so a new radius redraws the control.
    @MainActor var shape: AnyShape {
        #if os(macOS)
            if followsChromeCorners {
                return AnyShape(
                    RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous))
            }
        #endif
        return AnyShape(Capsule())
    }
}
