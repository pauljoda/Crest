import SwiftUI

/// Another Space's cards as the page area slides them in beside the shown
/// Space's, or keeps them under the shown Space's until those have drawn: a
/// lone card, or a split's row, as the shown Space would draw them. Each holds
/// the page its tab keeps in memory, live, its Start Page, or the tab's icon
/// and title where it keeps no page. They take no touches and load nothing,
/// and a locked Space's card stays empty.
struct MobileSpaceNeighborPage: View {
    // MARK: - Variables

    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement
    @Environment(\.browserWindowCornerRadius) private var windowCornerRadius
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.colorScheme) private var colorScheme
    let space: SpaceModel
    let model: MobileBrowserRootModel
    let adjoinsSidebar: Bool
    let usesBorderlessPageFrame: Bool

    private var browser: BrowserStore { model.browser }
    private var pages: MobileBrowserPageStore { model.pages }
    private var isLocked: Bool { model.spaceAccess.isLocked(space) }
    private var appearance: BrowserChromeAppearance { .device(windowCornerRadius: windowCornerRadius) }

    /// The tab the window shows in the Space.
    private var shownTab: TabStateModel? {
        browser.selectedTabID(in: space.id).flatMap { space.shownTab($0) }
    }

    // MARK: - Actions - Presentation

    var body: some View {
        Group {
            let presentation = BrowserPageSurfacePresentation(
                space: space, isLocked: isLocked, cards: browser.cards(in: space), hasEnteredSplitContent: false,
                resolvedTarget: nil)
            if case .columns(_, let members, _) = presentation {
                row(of: members)
            } else {
                lone(shownTab)
            }
        }
        .environment(\.spaceContentIsInteractive, false)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The Space's one card, showing `tab`.
    private func lone(_ tab: TabStateModel?) -> some View {
        let page = tab.flatMap(livePage(of:))
        return BrowserRootDetailSurface(
            adjoinsLeadingSidebar: adjoinsSidebar,
            usesBorderlessFrame: usesBorderlessPageFrame,
            isStartPage: tab.map { $0.surface == .startPage } ?? true,
            hasActivePage: page != nil,
            completedNavigationCount: page?.completedNavigationCount ?? 0,
            hasSelectedSpace: true,
            handleWebContentInteraction: {},
            frameInsets: controlPlacement.pageInsets,
            content: content(of: tab, page: page, showsStartPage: true)
        )
    }

    /// The Space's split, a card for each of `members`, at the widths the
    /// window keeps for it.
    private func row(of members: [TabStateModel]) -> some View {
        BrowserSplitColumnsView(
            members: members,
            focusedTabID: shownTab?.id,
            frameInsets: controlPlacement.pageInsets(
                appearance.pageInsets(docked: adjoinsSidebar, direction: layoutDirection)),
            accent: space.settings.look.primaryColor.color,
            placeholderIndex: nil,
            liftedTabID: nil,
            widthTransaction: .constant(
                BrowserSplitWidthTransaction(persistedFractions: model.splitColumnFractions(in: space))),
            onResizeCommit: { _ in },
            onFocus: { _ in },
            usesTransparentInnerSurface: { member in
                let page = livePage(of: member)
                return BrowserPageSurfacePresentation.usesTransparentInnerSurface(
                    isStartPage: member.surface == .startPage, hasActivePage: page != nil,
                    completedNavigationCount: page?.completedNavigationCount ?? 0)
            },
            content: { member, _ in
                // A split's Start Page card reads as an empty card, as the
                // shown Space's does.
                content(of: member, page: livePage(of: member), showsStartPage: false)
            }
        )
        .environment(\.browserSplitUsesBorderlessFrame, appearance.borderless)
    }

    /// What a card shows for `tab`: its live `page`, the icon and title of a
    /// tab with none, or the Start Page where `showsStartPage`.
    @ViewBuilder
    private func content(of tab: TabStateModel?, page: MobileBrowserPage?, showsStartPage: Bool) -> some View {
        if isLocked {
            Color.clear
        } else if let page {
            MobileBrowserLivePageView(page: page, viewport: .inline, isActive: false, hidesFromAccessibility: true)
        } else if let tab, tab.surface != .startPage {
            MobileTabSwipePlaceholder(
                tab: tab, space: space, favicons: browser.core.state.favicons, bottomChromeHeight: 0)
        } else if showsStartPage {
            BrowserStartPage(
                browser: browser,
                space: space,
                isPrivateBrowsing: browser.isPrivateBrowsing,
                selectedTabID: tab?.id,
                isSourceAvailable: { _ in false },
                selectTab: { _, _ in false },
                openURL: { _, _ in false },
                isCommandPaletteObscured: false,
                layout: .mobileRegularPage,
                headerColorScheme: space.settings.look.colorScheme(over: colorScheme)
            )
        } else {
            Color.clear
        }
    }

    /// The page `tab` keeps in memory, where it has drawn one to show.
    private func livePage(of tab: TabStateModel) -> MobileBrowserPage? {
        guard !isLocked, let page = pages.spacePreviewPage(for: tab.id, in: space),
            PagePresentation.of(tab.surface, page: page) == .livePage,
            BrowserPageSurfacePresentation.revealsWebContent(committedNavigationCount: page.committedNavigationCount)
        else { return nil }
        return page
    }
}
