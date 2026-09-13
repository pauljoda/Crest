import SwiftUI

/// UIKit's drag interaction arbitrates with context menus and supplies the lift preview.
struct BrowserPlatformSidebarReorderLiftGesture: ViewModifier {
    var isEnabled = true
    let apply: (BrowserSidebarReorderLiftPhase) -> Void

    func body(content: Content) -> some View { content }
}
