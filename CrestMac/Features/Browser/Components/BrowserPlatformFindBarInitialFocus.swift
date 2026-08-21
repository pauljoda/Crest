import SwiftUI

/// macOS hands the query field the keyboard by declaring it the bar's default
/// focus, which the window's focus system evaluates as the bar appears.
struct BrowserPlatformFindBarInitialFocus: ViewModifier {
    let field: FocusState<BrowserFindBarField?>.Binding

    func body(content: Content) -> some View {
        content.defaultFocus(field, .query)
    }
}
