import SwiftUI

extension FocusedValues {
    var mobileBrowserCommandContext: MobileBrowserCommandContext? {
        get { self[MobileBrowserCommandContextFocusedValueKey.self] }
        set { self[MobileBrowserCommandContextFocusedValueKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// The window's commands, for a control inside it that runs them on the
    /// page it shows, such as Site Controls.
    @Entry var mobileBrowserCommandContext: MobileBrowserCommandContext? = nil
    /// Opens an address in the window's private browsing, which the window
    /// scene owns; nil inside private browsing itself.
    @Entry var mobileOpenInPrivateBrowsing: (@MainActor (URL) -> Void)? = nil
}
