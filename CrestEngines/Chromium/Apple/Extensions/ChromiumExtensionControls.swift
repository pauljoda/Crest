import SwiftUI

struct BrowserPinnedExtensionStrip: View {
    let page: ChromiumNativePage?
    let space: BrowserSpace
    let browser: BrowserStore
    private var store: ChromiumExtensionStore { CrestChromiumRoot.extensions }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BrowserExtensionSidePanelHost.self) private var sidePanel: BrowserExtensionSidePanelHost?

    var body: some View {
        // The row is the Space's, not the page's: a Space showing its Start Page
        // still has the extensions the user pinned to it.
        let actions = store.pinnedActions(for: space, page: page)
        // The container is always in the view tree, empty or not. SwiftUI does
        // not run `task` on a conditional that resolves to nothing, and the
        // Space's engine profile is what the row needs to have any action to
        // show: hanging the preparation off the populated row alone left a
        // Space that had never opened a page with a row that never filled.
        VStack(spacing: 0) {
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
        .task(id: PreparationKey(space: space.id, profile: space.profile.id)) {
            await store.prepare(space, in: browser)
        }
    }

    /// Preparation is per Space and per engine profile, and is idempotent: the
    /// store keeps the profile it loaded and answers a repeat immediately.
    private struct PreparationKey: Equatable {
        let space: SpaceID
        let profile: UUID
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
