#if CREST_CHROMIUM_HOST
import AppKit
import SwiftUI

/// The panel hosts the engine can reach, one per browser window.
///
/// `chrome.sidePanel.open()`, `chrome.sidePanel.close()` and an action click
/// that toggles a panel all arrive from the engine with a page identifier and
/// no view context, so the window whose row owns the card has to be found
/// rather than injected the way the extension controls receive it.
@MainActor
enum ChromiumExtensionSidePanelHosts {
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
        guard let host = hosts[window]?.host else { hosts[window] = nil; return nil }
        return host
    }
}

/// Publishes a window's panel host for the engine's own side-panel requests.
struct ChromiumExtensionSidePanelRegistration: ViewModifier {
    let host: BrowserExtensionSidePanelHost
    let window: BrowserWindowID

    func body(content: Content) -> some View {
        content
            .onAppear { ChromiumExtensionSidePanelHosts.register(host, for: window) }
            .onDisappear { ChromiumExtensionSidePanelHosts.forget(window) }
    }
}

extension BrowserExtensionSidePanelHost {
    /// The action the extension action's context menu should offer, or `nil`
    /// when this extension has no side panel entry for `page`'s own tab.
    ///
    /// The panel document belongs to the engine and the card to `host`, so the
    /// engine's own dismissal only drops the card and a dismissal from the card
    /// only releases the document.
    static func opener(
        _ action: BrowserExtensionActionPresentation,
        page: ChromiumNativePage,
        host: BrowserExtensionSidePanelHost?
    ) -> (@MainActor () -> Void)? {
        guard let host, page.hasSidePanel(action.id) else { return nil }
        return { [weak host, weak page] in
            guard let host, let page else { return }
            present(action.id, title: action.displayName, icon: action.icon, page: page, host: host)
        }
    }

    /// Applies a request the engine made for `page`'s own window.
    ///
    /// The engine has already checked that the extension has an entry for the
    /// tab, so the only remaining decision is what the window is showing: a
    /// second request for the panel already on screen toggles or is ignored
    /// rather than rebuilding the same document.
    static func route(
        _ request: CrestSidePanelRequest,
        extensionID: String,
        page: ChromiumNativePage,
        host: BrowserExtensionSidePanelHost
    ) {
        let isShowing = host.panel?.id == extensionID
        switch request {
        case .close:
            if isShowing { host.close() }
        case .toggle where isShowing:
            host.close()
        case .open where isShowing:
            break
        default:
            let action = CrestChromiumRoot.extensions.actions(for: page).first { $0.id == extensionID }
            present(extensionID, title: action?.displayName ?? extensionID,
                icon: action?.icon, page: page, host: host)
        }
    }

    private static func present(
        _ extensionID: String,
        title: String,
        icon: NSImage?,
        page: ChromiumNativePage,
        host: BrowserExtensionSidePanelHost
    ) {
        let view = page.openSidePanel(extensionID) { [weak host] in
            MainActor.assumeIsolated { host?.dismiss(extensionID) }
        }
        guard let view else {
            CrestChromiumRoot.showNativeNotice(
                "This extension's side panel is unavailable on this page.",
                icon: "sidebar.right")
            return
        }
        host.present(
            BrowserExtensionSidePanelHost.Panel(
                id: extensionID, title: title, icon: icon, view: view,
                close: { [weak page] in page?.closeSidePanel() }))
    }
}
#endif
