import SwiftUI

/// Browser extensions are a macOS-only feature for now.
///
/// This modifier exists only so the shared `BrowserExtensionsView` compiles for
/// the mobile target. No mobile screen presents that view, so there is no layout
/// to adapt and the content passes through untouched. Do not grow this into a
/// working adapter: mobile support needs a deliberate product decision first,
/// not an implementation here.
struct BrowserPlatformExtensionsViewSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
