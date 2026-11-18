import SwiftUI

extension EnvironmentValues {
    /// Whether the browser view styles the window it shows in as that
    /// window's own chrome: its title bar, toolbar and window buttons. A view
    /// shown inside another window, as setup's preview is, leaves that window
    /// as it is.
    @Entry var browserRootStylesWindow = true
}
