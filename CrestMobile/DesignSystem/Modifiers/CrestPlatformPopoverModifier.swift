import SwiftUI

/// A popover on iPhone and iPad presents the color picker over itself, so
/// nothing outside it needs to hold it open.
struct CrestPlatformPopoverModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
