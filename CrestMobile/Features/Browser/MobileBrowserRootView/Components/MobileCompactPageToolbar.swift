import SwiftUI

struct MobileCompactPageToolbar: View {
    let browser: BrowserStore
    let pageActions: MobileSelectedPageActionPort?
    let downloadsAccess: MobileDownloadsMenuAccess?
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let submitAddress: () -> Void
    let beginNewTab: () -> Void
    /// New Tab beside Tabs, which puts search up; nil leaves Tabs on its own.
    let newTabSearch: (() -> Void)?
    let showTabViewer: () -> Void
    let showHistory: () -> Void
    let hideToolbar: () -> Void
    /// The swipe through the shown Space's tabs this bar drives.
    let tabSwipe: MobileTabSwipe
    /// The bar may swipe through the shown Space's tabs and show its split's
    /// cards: false while the Space is locked, whose tabs it must not show.
    let canSwipeTabs: Bool
    /// The tabs a swipe reaches either side, as the core answers it.
    let swipeNeighbors: () -> SwipeNeighborTabs
    /// Shows the tab a swipe landed on.
    let showSwipedTab: (UUID) -> Void
    let compactTransitionEnded: (CGSize) -> Void
    /// Opens the command palette over the address bar.
    var openPalette: (() -> Void)?
    var isPaletteShown = false
    /// The namespace in which the palette grows out of the address bar.
    var commandSurfaceNamespace: Namespace.ID?
    var commandPaletteHandoff = BrowserCommandPaletteHandoff.neither

    /// Where Back, Forward, New Tab and Tabs are: beside the address here, or
    /// in the side toolbar, which leaves the address on its own over the page.
    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: MobileBrowserChromeLayout.compactToolbarSpacing) {
            if !controlPlacement.movesControlsToToolbar {
                GlassEffectContainer(spacing: 0) {
                    MobilePageHistoryControls(pageActions: pageActions, showHistory: showHistory)
                }
            }

            MobileSplitBubbleBar(
                cards: canSwipeTabs ? browser.shownCards : [],
                shownTabID: browser.shownTab?.id,
                swipe: tabSwipe,
                favicons: browser.core.state.favicons,
                profileID: browser.shownSpace?.profileID,
                step: stepTab
            ) {
                MobileCompactAddressBar(
                    browser: browser,
                    text: $address,
                    isEditing: $isAddressEditing,
                    isSecure: pageActions?.activeURL?.scheme?.lowercased() == "https",
                    progress: pageActions?.activePage?.estimatedProgress ?? 0,
                    isLoading: pageActions?.activePage?.live.isLoading == true,
                    pageActions: pageActions,
                    downloadsAccess: downloadsAccess,
                    hideToolbar: hideToolbar,
                    reloadOrStop: reloadOrStop,
                    transition: .revealTabViewer,
                    transitionEnded: compactTransitionEnded,
                    beginNewTab: beginNewTab,
                    submit: submitAddress,
                    stepTab: tabStep,
                    openPalette: openPalette,
                    isPaletteShown: isPaletteShown,
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    commandPaletteHandoff: commandPaletteHandoff
                )
            }
            .modifier(MobileTabSwipeShake(hits: tabSwipe.boundaryHits))

            if !controlPlacement.movesControlsToToolbar {
                GlassEffectContainer(spacing: 0) {
                    tabControls
                }
            }
        }
        .labelStyle(.iconOnly)
        .font(
            .system(
                size: MobileBrowserChromeLayout.compactToolbarSymbolSize,
                weight: .semibold
            )
        )
        .padding(
            .horizontal,
            MobileBrowserChromeLayout.compactToolbarHorizontalPadding
        )
        .padding(
            .vertical,
            MobileBrowserChromeLayout.compactToolbarVerticalPadding
        )
        .frame(maxWidth: .infinity)
        .modifier(
            MobileTabSwipeGesture(
                swipe: tabSwipe, isEnabled: canSwipeTabs && !isAddressEditing, neighbors: swipeNeighbors,
                land: showSwipedTab))
    }

    /// The way to the tabs, with a new tab beside it in one capsule that
    /// mirrors Back and Forward on the other side of the address.
    @ViewBuilder
    private var tabControls: some View {
        if let newTabSearch {
            HStack(spacing: 0) {
                MobileCompactIconButton(title: "New Tab", systemImage: "plus", action: newTabSearch)
                    .accessibilityIdentifier("new-tab-button")
                Divider()
                    .frame(height: MobileBrowserChromeLayout.historyDividerHeight)
                    .opacity(MobileBrowserChromeLayout.historyDividerOpacity)
                tabsButton
            }
            .padding(.horizontal, MobileBrowserChromeLayout.historyCapsuleHorizontalPadding)
            .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            tabsButton
                .glassEffect(.regular.interactive(), in: .circle)
        }
    }

    private var tabsButton: some View {
        MobileCompactIconButton(title: "Tabs", systemImage: "square.on.square", action: showTabViewer)
            .accessibilityIdentifier("tab-viewer-button")
    }

    private func reloadOrStop() {
        pageActions?.reloadOrStop()
    }

    /// VoiceOver's way to the tab before or after, where the bar may swipe.
    private var tabStep: ((AdjacentDirection) -> Void)? {
        guard canSwipeTabs else { return nil }
        return stepTab
    }

    /// Moves one tab `direction` as a swipe would, for VoiceOver and a split's
    /// bubbles.
    private func stepTab(_ direction: AdjacentDirection) {
        tabSwipe.step(direction, reduceMotion: reduceMotion, neighbors: swipeNeighbors, land: showSwipedTab)
    }
}
