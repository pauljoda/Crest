import SwiftUI

/// Site Controls' Extensions page: every extension that acts on the page,
/// which runs from its row and whose context menu holds the rest, then
/// Manage Extensions, and Install Extension on a Chrome Web Store page.
struct ChromiumExtensionsPage: View {
    let page: ChromiumNativePage
    /// The page's Space in the read model.
    let space: SpaceModel
    let url: URL?
    let dismiss: () -> Void
    private var store: ChromiumExtensionStore { ChromiumComposition.extensions }
    @Environment(BrowserExtensionSidePanelHost.self) private var sidePanel: BrowserExtensionSidePanelHost?

    var body: some View {
        let actions = store.actions(for: page)
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            if !actions.isEmpty {
                SiteControlsPageSection(title: "On this page") {
                    ForEach(actions) { action in
                        ChromiumExtensionsPageRow(
                            action: action,
                            perform: { anchor in run(action, anchor: anchor) },
                            togglePinned: { store.togglePin(action, space: space.identity) },
                            presentMenu: { anchor in presentMenu(action, anchor: anchor) })
                    }
                }
            }
            SiteControlsPageSection {
                if store.mayChange(space.identity), let id = ChromiumNativePage.webStoreExtensionID(url) {
                    SiteControlsRow(title: Text("Install Extension…"), symbol: "plus.app") {
                        afterDismiss { store.install(id, in: space.identity, anchor: page.surface) }
                    } trailing: {
                        EmptyView()
                    }
                }
                SiteControlsRow(
                    title: Text("Manage Extensions…"), symbol: "puzzlepiece.extension",
                    titleTint: CrestBrandTheme.accentText
                ) {
                    afterDismiss { ChromiumComposition.openExtensionSettings() }
                } trailing: {
                    EmptyView()
                }
                .accessibilityIdentifier("site-control-manage-extensions")
            }
        }
    }

    private func run(_ action: BrowserExtensionActionPresentation, anchor: BrowserExtensionPopupAnchor?) {
        let retained = anchor?.replacingSourceWindow(page.surface.window)
        afterDismiss { page.runExtension(action.id, anchor: retained) }
    }

    /// Site Controls stay open under the menu, and close only for an item
    /// that leads elsewhere.
    private func presentMenu(_ action: BrowserExtensionActionPresentation, anchor: BrowserExtensionPopupAnchor?) {
        store.presentMenu(
            action, space: space.identity, anchor: anchor,
            openSidePanel: BrowserExtensionSidePanelHost.opener(action, page: page, host: sidePanel),
            closeSource: dismiss)
    }

    private func afterDismiss(_ action: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}

/// One extension as the Extensions page lists it: its artwork, name and
/// whether it is pinned, running from the row, with its pin and context menu.
private struct ChromiumExtensionsPageRow: View {
    let action: BrowserExtensionActionPresentation
    let perform: (BrowserExtensionPopupAnchor?) -> Void
    let togglePinned: () -> Void
    let presentMenu: (BrowserExtensionPopupAnchor?) -> Void

    @State private var popupAnchor: BrowserExtensionPopupAnchor?
    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            Button {
                perform(popupAnchor)
            } label: {
                HStack(spacing: CrestSpacing.small + 1) {
                    BrowserExtensionActionArtwork(action: action, glyphSize: metrics.glyphSize)
                        .frame(width: metrics.glyphSize + 4, height: metrics.glyphSize + 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: action.displayName)
                            .font(metrics.rowFont)
                            .lineLimit(1)
                        if action.isPinned {
                            Text("Pinned to the toolbar")
                                .font(metrics.detailFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: metrics.rowHeight - metrics.rowInset * 2)
                .padding(.vertical, metrics.rowInset)
                .contentShape(.rect)
            }
            .buttonStyle(SiteControlsRowButtonStyle())
            .disabled(!action.isEnabled || action.isLoading)
            .background { BrowserExtensionPopupAnchorReader(popupAnchor: $popupAnchor) }
            .overlay { BrowserExtensionContextMenuTrigger(presentMenu: presentMenu) }
            BrowserExtensionPinButton(isPinned: action.isPinned, action: togglePinned)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("extension-row-\(action.id)")
    }
}
