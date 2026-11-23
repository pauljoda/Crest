import SwiftUI

struct BrowserPinnedExtensionStrip: View {
    // MARK: - Types

    /// Where a Space's pinned actions are shown: in a strip above the
    /// sidebar's tabs, or in a Quick Window's toolbar, where the actions that
    /// do not fit go behind an overflow button.
    struct Placement: Hashable, Sendable {
        static let sidebar = Placement(overflows: false)
        static let toolbar = Placement(overflows: true)

        let overflows: Bool
    }

    // MARK: - Variables

    let page: ChromiumNativePage?
    /// The Space whose row this is, in the read model.
    let space: SpaceModel
    var placement = Placement.sidebar
    private var store: ChromiumExtensionStore { ChromiumComposition.extensions }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BrowserExtensionSidePanelHost.self) private var sidePanel: BrowserExtensionSidePanelHost?

    var body: some View {
        // The row is the Space's, not the page's: a Space showing its Start Page
        // still has the extensions the user pinned to it.
        let actions = store.pinnedActions(for: space.identity, page: page)
        // The container is always in the view tree, empty or not. SwiftUI does
        // not run `task` on a conditional that resolves to nothing, and the
        // Space's engine profile is what the row needs to have any action to
        // show: hanging the preparation off the populated row alone left a
        // Space that had never opened a page with a row that never filled.
        VStack(spacing: 0) {
            if !actions.isEmpty, placement.overflows {
                BrowserPinnedExtensionToolbarActions(
                    actions: actions,
                    perform: run,
                    presentMenu: presentMenu
                )
            } else if !actions.isEmpty {
                BrowserPinnedExtensionStripContent(
                    actions: actions,
                    perform: run,
                    presentMenu: presentMenu,
                    reordering: store.mayChange(space.identity)
                        ? BrowserPinnedExtensionActionList.Reordering(
                            space: space.identity,
                            move: { store.movePin($0, before: $1, space: space.identity) })
                        : nil,
                    spaceID: space.id
                )
                .padding(.top, BrowserSidebarMetrics.topSectionGap)
                // Pinned tabs below hold the same gap above themselves. A
                // Sub-Space shows the ones its group shares, not its own.
                .padding(
                    .bottom,
                    space.pinSource.sidebar.section(.pinned).isEmpty ? BrowserSidebarMetrics.topSectionGap : 0
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : SpacePagerSettlement.standardAnimation, value: actions.map(\.id))
        .task(id: PreparationKey(space: space.id, profile: space.profileID)) {
            store.prepare(space.identity)
        }
    }

    /// Preparation is per Space and per engine profile, and is idempotent: the
    /// store keeps the profile it loaded and answers a repeat immediately.
    private struct PreparationKey: Equatable {
        let space: UUID
        let profile: UUID
    }

    private func presentMenu(_ action: BrowserExtensionActionPresentation, anchor: BrowserExtensionPopupAnchor?) {
        store.presentMenu(
            action, space: space.identity, anchor: anchor,
            openSidePanel: page.flatMap {
                BrowserExtensionSidePanelHost.opener(action, page: $0, host: sidePanel)
            })
    }

    private func run(
        _ action: BrowserExtensionActionPresentation,
        anchor: BrowserExtensionPopupAnchor?
    ) {
        guard let page else {
            store.runPinned(action, space: space.identity, anchor: anchor)
            return
        }
        page.runExtension(action.id, anchor: anchor)
    }
}

/// The page's extension tiles in Site Controls, running the page's actions,
/// pinning them and opening their menus.
struct ChromiumExtensionControls: View {
    let page: ChromiumNativePage
    /// The page's Space in the read model.
    let space: SpaceModel
    let url: URL?
    let dismiss: () -> Void
    let openPage: () -> Void
    private var store: ChromiumExtensionStore { ChromiumComposition.extensions }
    @Environment(BrowserExtensionSidePanelHost.self) private var sidePanel: BrowserExtensionSidePanelHost?

    var body: some View {
        BrowserSiteExtensionsSection(
            actions: store.actions(for: page),
            perform: { action, anchor in
                let retained = anchor?.replacingSourceWindow(page.surface.window)
                afterDismiss { page.runExtension(action.id, anchor: retained) }
            },
            togglePinned: { store.togglePin($0, space: space.identity) },
            // Site Controls stay open under the menu, as they do for the pin
            // button, and close only for an item that leads elsewhere.
            presentMenu: { action, anchor in
                store.presentMenu(
                    action, space: space.identity, anchor: anchor,
                    openSidePanel: BrowserExtensionSidePanelHost.opener(
                        action, page: page, host: sidePanel),
                    closeSource: dismiss)
            },
            install: installAction,
            openPage: openPage)
    }

    /// Installs the extension a Chrome Web Store page shows, where the Space
    /// may change its extensions.
    private var installAction: (() -> Void)? {
        guard store.mayChange(space.identity), let id = ChromiumNativePage.webStoreExtensionID(url) else { return nil }
        return { afterDismiss { store.install(id, in: space.identity, anchor: page.surface) } }
    }

    private func afterDismiss(_ action: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}
