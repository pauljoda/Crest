import SwiftUI

/// Where the Close and Open In controls are shown: the action bar beside a
/// Peek's card, or a Quick Window's toolbar. Each place sets the controls'
/// height and the size of the Space's icon in them.
struct BrowserPeekControlStyle: Hashable, Sendable {
    // MARK: - Static Variables

    static let actionBar = BrowserPeekControlStyle(
        height: 48, iconSize: 22, leadingInset: 16, menuWidth: 48, spaceNameWidth: nil)
    static let toolbar = BrowserPeekControlStyle(
        height: BrowserChromeLayout.addressHeight, iconSize: 18, leadingInset: 10, menuWidth: 30, spaceNameWidth: 118)

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

    /// The controls' shape: on the Mac the corner radius the person chose in
    /// Look and Feel, as the address field wears, and on iPhone and iPad a
    /// capsule under the thumb. Read in a view's body, so a new radius redraws
    /// the control.
    @MainActor var shape: AnyShape {
        #if os(macOS)
            AnyShape(RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous))
        #else
            AnyShape(Capsule())
        #endif
    }
}
