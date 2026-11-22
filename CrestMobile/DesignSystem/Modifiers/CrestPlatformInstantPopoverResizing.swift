import SwiftUI

/// The phone and iPad present popovers that already follow their content's
/// size, so nothing is needed.
struct CrestPlatformInstantPopoverResizing: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
