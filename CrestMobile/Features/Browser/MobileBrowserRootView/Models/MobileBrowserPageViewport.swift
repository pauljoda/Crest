import UIKit

/// Everything a mobile surface has to know to render one live web page at the
/// right size: whether it draws through the system safe areas, what those areas
/// measure, and how much floating chrome covers its bottom.
///
/// The three travel together because they are only ever right together. A tab
/// presented on its own and the same tab presented as a split card resolve one
/// value in `MobileBrowserDetailView` and hand it to one page view, so a card
/// cannot drift into a different viewport treatment than the plain tab it is.
///
/// `systemSafeAreaInsets` is carried as data rather than read from the hosting
/// view for the same reason. A card is laid out inside the carousel's
/// `ScrollView`, and a `ScrollView` resolves its content's safe area to zero —
/// a `UIViewRepresentable` in there reports `safeAreaInsets == .zero` however
/// far it extends behind the status bar. Passing the measurement taken outside
/// the scroll view is what keeps the card's web content on the same row as the
/// single page's.
struct MobileBrowserPageViewport: Equatable {
    /// Whether the page draws through the system safe areas and absorbs them
    /// itself, which is how every compact full-bleed surface presents a page.
    let obscuresSystemSafeAreas: Bool
    /// The window's safe areas as SwiftUI reports them for the page area,
    /// including any chrome inset above the page.
    let systemSafeAreaInsets: UIEdgeInsets
    /// The floating chrome that covers the bottom of the page, reported to
    /// WebKit as obscured rather than subtracted from the web view's frame.
    let bottomChromeHeight: CGFloat

    /// A page that stays inside the bounds its container gives it: the iPad's
    /// rounded detail surface and every iPad split column, where the window
    /// chrome — not the page — owns the safe areas.
    static let inline = MobileBrowserPageViewport(
        obscuresSystemSafeAreas: false,
        systemSafeAreaInsets: .zero,
        bottomChromeHeight: 0
    )
}
