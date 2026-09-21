#if CREST_CHROMIUM_HOST
import AppKit

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
            let view = page.openSidePanel(action.id) { [weak host] in
                MainActor.assumeIsolated { host?.dismiss(action.id) }
            }
            guard let view else {
                CrestChromiumRoot.showNativeNotice(
                    "This extension's side panel is unavailable on this page.",
                    icon: "sidebar.right")
                return
            }
            host.present(
                BrowserExtensionSidePanelHost.Panel(
                    id: action.id, title: action.displayName, icon: action.icon, view: view,
                    close: { [weak page] in page?.closeSidePanel() }))
        }
    }
}
#endif
