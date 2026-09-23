import SwiftUI

/// The panel hosts the engine can reach, one per browser window.
///
/// `chrome.sidePanel.open()`, `chrome.sidePanel.close()` and an action click
/// that toggles a panel all arrive from the engine with a page identifier and
/// no view context, so the window whose row owns the card has to be found
/// rather than injected the way the extension controls receive it.
@MainActor
enum BrowserExtensionSidePanelHosts {
    /// Weak by construction: the window's own root model owns its panel host.
    private final class Reference { weak var host: BrowserExtensionSidePanelHost? }
    private static var hosts: [BrowserWindowID: Reference] = [:]

    static func register(_ host: BrowserExtensionSidePanelHost, for window: BrowserWindowID) {
        let reference = Reference()
        reference.host = host
        hosts[window] = reference
    }
    static func forget(_ window: BrowserWindowID) { hosts[window] = nil }
    static func host(for window: BrowserWindowID) -> BrowserExtensionSidePanelHost? {
        guard let host = hosts[window]?.host else {
            hosts[window] = nil
            return nil
        }
        return host
    }
}

/// Publishes a window's panel host for the engine's own side-panel requests.
struct BrowserExtensionSidePanelRegistration: ViewModifier {
    let host: BrowserExtensionSidePanelHost
    let window: BrowserWindowID

    func body(content: Content) -> some View {
        content
            .onAppear { BrowserExtensionSidePanelHosts.register(host, for: window) }
            .onDisappear { BrowserExtensionSidePanelHosts.forget(window) }
    }
}
