import SwiftUI

/// The card a sidebar folder shows when the pointer rests on it: a search
/// field that takes typing at once, over the folder's tabs, however deep, as
/// the sidebar's own rows.
///
/// The rows are the sidebar's tab rows, so they look and act as they do
/// there: they open, unload and close their tabs, offer their menus, drag out
/// of the folder, and show their own preview beside this card. Typing narrows
/// them by title or site, and Return opens the first. Opening a tab closes
/// the card, and while the search holds text, the card stays when the pointer
/// leaves it.
///
/// A card a finger held the folder for offers the folder's own menu behind
/// "…", as a Peek offers its link's.
struct BrowserFolderPreviewCard: View {
    // MARK: - Static Variables

    /// The tallest the list grows before it scrolls.
    private static let listMaximumHeight: CGFloat = 320

    // MARK: - Variables

    let folder: FolderStateModel
    let context: BrowserSidebarListContext
    let preview: BrowserTabPreviewState
    /// The folder's own menu, offered behind "…", or nil where the card
    /// offers none.
    let menu: BrowserFolderOrganizationMenu?

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    @State private var listHeight: CGFloat = 0

    /// Every tab the folder holds, however deep, in the sidebar's order.
    private var tabs: [TabStateModel] {
        context.space.tabIDs(inFolder: folder.id).compactMap { context.space.tabs.model($0) }
    }

    /// The folder's list as the card's rows draw it: the sidebar's, without
    /// the page-opening motion the sidebar's own rows of these tabs carry.
    private var rowContext: BrowserSidebarListContext {
        var context = context
        context.promotionNamespaces = [:]
        return context
    }

    // MARK: - Actions - Presentation

    var body: some View {
        let matches = Self.matches(of: query, in: tabs)
        // The card holds its search and rows as the sidebar holds its
        // layers: each the sidebar's inset from the card's sides, and the
        // search the sidebar's gap above its rows, as its address field
        // keeps. The rows keep that inset and half their separation inside
        // their own frames.
        let separation = BrowserSidebarDensity(BrowserDeviceAppearanceStore.shared.tabScale).rowSeparation(
            hasBorders: BrowserDeviceAppearanceStore.shared.tabs.borders == .all)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: BrowserSidebarMetrics.layerInset) {
                BrowserFolderPreviewSearchField(text: $query) { open(matches.first) }
                if let menu { moreMenu(menu) }
            }
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .padding(.bottom, BrowserSidebarMetrics.topSectionSpacing - separation / 2)
            list(matches)
        }
        .padding(.top, BrowserSidebarMetrics.layerInset)
        .padding(.bottom, BrowserSidebarMetrics.layerInset - separation / 2)
        .modifier(SurfaceToneAppearance())
        .browserTabPreviewSurface()
        .environment(\.browserTabPreviewState, preview.inner)
        .onChange(of: query) { _, query in preview.isHeld = !query.isEmpty }
        .onChange(of: context.window.shownTabIDs.members) { preview.dismiss() }
        // A folder its menu moved to another Space, or deleted, takes its
        // card with it.
        .onChange(of: context.space.folders.contains(folder.id)) { _, isHere in
            if !isHere { preview.dismiss() }
        }
        .onDisappear { preview.isHeld = false }
    }

    /// "…", which opens the folder's menu beside the search.
    private func moreMenu(_ menu: BrowserFolderOrganizationMenu) -> some View {
        let side = capabilities.tabRowHeight(
            tabScale: BrowserDeviceAppearanceStore.shared.tabScale, dynamicTypeSize: dynamicTypeSize)
        return Menu {
            menu.tint(.primary)
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .fontWeight(.semibold)
        }
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: CGSize(width: side, height: side),
                cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), showsRestingFill: true)
        )
        .accessibilityIdentifier("folder-preview-menu")
    }

    @ViewBuilder
    private func list(_ matches: [TabStateModel]) -> some View {
        if matches.isEmpty {
            Text(query.isEmpty ? "No Tabs" : "No Results")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CrestSpacing.small)
        } else {
            let rowContext = self.rowContext
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matches, id: \.id) { tab in
                        BrowserSidebarTabRow(tab: tab, context: rowContext)
                    }
                }
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    listHeight = $0
                }
            }
            .frame(height: min(listHeight, Self.listMaximumHeight))
        }
    }

    // MARK: - Actions - Choosing

    /// The tabs whose title or site holds `query`, or every tab while it is
    /// blank.
    private static func matches(of query: String, in tabs: [TabStateModel]) -> [TabStateModel] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tabs }
        return tabs.filter { tab in
            tab.shownTitle.localizedStandardContains(query)
                || tab.address.map { BrowserAddressPresentation($0.absoluteString).domain }?
                    .localizedStandardContains(query) == true
        }
    }

    /// Opens `tab` in its Space, which closes the card.
    private func open(_ tab: TabStateModel?) {
        guard let tab, context.isCurrentAndUnlocked else { return }
        context.select(tab.id)
    }
}
