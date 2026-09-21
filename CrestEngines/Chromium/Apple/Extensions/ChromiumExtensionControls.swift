import SwiftUI

struct BrowserPinnedExtensionStrip: View {
    let page: ChromiumNativePage?
    let space: BrowserSpace
    private var store: ChromiumExtensionStore { CrestChromiumRoot.extensions }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BrowserExtensionSidePanelHost.self) private var sidePanel: BrowserExtensionSidePanelHost?

    var body: some View {
        let actions = page.map { store.actions(for: $0).filter(\.isPinned) } ?? []
        Group {
            if !actions.isEmpty, let page {
                BrowserPinnedExtensionStripContent(actions: actions,
                    perform: { action, anchor in page.runExtension(action.id, anchor: anchor) },
                    presentMenu: { action, anchor in
                        store.presentMenu(action, space: space, anchor: anchor,
                            isPrivate: page.isPrivateBrowsing,
                            openSidePanel: BrowserExtensionSidePanelHost.opener(
                                action, page: page, host: sidePanel))
                    })
                    .padding(.top, BrowserPinnedExtensionStripLayoutPolicy.adjacentSpacing
                        + (space.tabSections.pinnedTabs.isEmpty ? 0 : BrowserTabSelectionGlow.outset))
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : SpacePagerSettlement.standardAnimation, value: actions.map(\.id))
    }
}

struct ChromiumExtensionControls: View {
    let page: ChromiumNativePage
    let space: BrowserSpace
    let url: URL?
    let dismiss: () -> Void
    private var store: ChromiumExtensionStore { CrestChromiumRoot.extensions }
    @Environment(BrowserExtensionSidePanelHost.self) private var sidePanel: BrowserExtensionSidePanelHost?

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Divider()
            BrowserSiteExtensionsSection(actions: store.actions(for: page),
                manageExtensions: { afterDismiss { CrestChromiumRoot.openExtensionSettings() } },
                perform: { action, anchor in
                    let retained = anchor?.replacingSourceWindow(page.surface.window)
                    afterDismiss { page.runExtension(action.id, anchor: retained) }
                },
                togglePinned: { store.togglePin($0, space: space) },
                presentMenu: { action, anchor in
                    let retained = anchor?.replacingSourceWindow(page.surface.window)
                    let openSidePanel = BrowserExtensionSidePanelHost.opener(
                        action, page: page, host: sidePanel)
                    afterDismiss {
                        store.presentMenu(action, space: space, anchor: retained,
                            isPrivate: page.isPrivateBrowsing, openSidePanel: openSidePanel)
                    }
                })
            if !page.isPrivateBrowsing, let id = ChromiumNativePage.webStoreExtensionID(url) {
                Button("Install Extension…", systemImage: "plus.app") {
                    afterDismiss { store.install(id, in: space, anchor: page.surface) }
                }
            }
        }
    }
    private func afterDismiss(_ action: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in await Task.yield(); action() }
    }
}
