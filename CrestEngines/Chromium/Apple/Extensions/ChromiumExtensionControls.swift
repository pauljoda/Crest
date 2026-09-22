import SwiftUI

struct BrowserPinnedExtensionStrip: View {
    let page: ChromiumNativePage?
    let space: BrowserSpace
    private var store: ChromiumExtensionStore { CrestChromiumRoot.extensions }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BrowserExtensionSidePanelHost.self) private var sidePanel: BrowserExtensionSidePanelHost?

    var body: some View {
        // The row is the Space's, not the page's: a Space showing its Start Page
        // still has the extensions the user pinned to it.
        let actions = store.pinnedActions(for: space, page: page)
        Group {
            if !actions.isEmpty {
                BrowserPinnedExtensionStripContent(actions: actions,
                    perform: run,
                    presentMenu: { action, anchor in
                        store.presentMenu(action, space: space, anchor: anchor,
                            isPrivate: page?.isPrivateBrowsing ?? false,
                            openSidePanel: page.flatMap {
                                BrowserExtensionSidePanelHost.opener(action, page: $0, host: sidePanel)
                            })
                    })
                    .padding(.top, BrowserPinnedExtensionStripLayoutPolicy.adjacentSpacing
                        + (space.tabSections.pinnedTabs.isEmpty ? 0 : BrowserTabSelectionGlow.outset))
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : SpacePagerSettlement.standardAnimation, value: actions.map(\.id))
        .task(id: PreparationKey(profile: space.profile.id, spaces: store.spaces.count)) {
            await store.prepare(space)
        }
    }

    /// Re-runs the Space's engine-profile preparation when the core publishes
    /// its Space list, which can arrive after the first Start Page is drawn.
    private struct PreparationKey: Equatable {
        let profile: UUID
        let spaces: Int
    }

    private func run(_ action: BrowserExtensionActionPresentation,
                     anchor: BrowserExtensionPopupAnchor?) {
        guard let page else {
            store.runPinned(action, space: space, anchor: anchor)
            return
        }
        page.runExtension(action.id, anchor: anchor)
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
