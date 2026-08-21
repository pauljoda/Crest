import SwiftUI

/// Mobile asks for the query field outright as the bar appears, which is what
/// raises the keyboard with it.
struct BrowserPlatformFindBarInitialFocus: ViewModifier {
    let field: FocusState<BrowserFindBarField?>.Binding

    func body(content: Content) -> some View {
        content.onAppear { field.wrappedValue = .query }
    }
}
