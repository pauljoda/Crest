import SwiftUI

/// Marks a row as the place the page zooms out of when its tab is selected.
///
/// The compact shell pushes the page over the sidebar, so the row is a real
/// transition source: `matchedTransitionSource` where the shell drives the
/// system's navigation zoom, and a matched-geometry anchor otherwise. Both
/// arms live in `mobileTabTransitionSource`; this modifier is only the seam
/// that lets a shared row ask for them.
struct BrowserPlatformTabPromotionSourceModifier: ViewModifier {
    let id: String
    var namespace: Namespace.ID?
    var usesNativeNavigationTransition = false
    var isEnabled = true

    func body(content: Content) -> some View {
        content.mobileTabTransitionSource(
            id: id,
            in: namespace,
            usesNativeNavigationTransition: usesNativeNavigationTransition,
            isEnabled: isEnabled
        )
    }
}
