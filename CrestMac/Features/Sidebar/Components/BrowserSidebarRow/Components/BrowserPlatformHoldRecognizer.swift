import SwiftUI

/// On the Mac a row opens its menu on a right click, which no hold takes the
/// place of, so nothing here answers a hold.
struct BrowserPlatformHoldRecognizer: ViewModifier {
    let hold: () -> Void

    func body(content: Content) -> some View {
        content
    }
}
