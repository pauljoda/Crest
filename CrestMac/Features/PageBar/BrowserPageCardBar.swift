import SwiftUI

// MARK: - Types

/// What a window hands every card's bar in a split: the things that belong to
/// the window rather than to any one card.
struct BrowserPageCardBarContext {
    let chrome: BrowserChromeState
    let fieldFrames: BrowserPageBarFieldFrames
    /// Whether the window's own buttons stand over the leading card's bar:
    /// with the address bar on top, unless a sidebar docked on the window's
    /// leading edge holds them in its strip.
    let windowControlsOverLeadingCard: Bool
    /// Whether the palette drops out of the card's own field, as it does with
    /// the address bar on top. In the sidebar placement the window's field in
    /// the sidebar stays the palette's.
    let opensFromOwnField: Bool
    /// Whether the sidebar is docked, which keeps its toggle at its foot
    /// rather than in the leading card's bar.
    let isSidebarDocked: Bool
    let sidebarOnRight: Bool
    /// What the sidebar's toggle does from where the sidebar is.
    let sidebarToggleAction: BrowserSidebarToggleAction
    /// Whether the window shows its command palette now.
    let isPaletteShown: () -> Bool
    let toggleSidebar: () -> Void
    /// Makes the card showing a tab the focused one.
    let focusCard: (UUID) -> Void
    let showHistory: () -> Void
}

/// The bar along the top of each card of a split, in either placement, as a
/// Quick Window has one: the shared page bar for this card's own page, inside
/// the card's corners, on its Space's color.
///
/// The focused card's bar draws at full strength and the others dim; using a
/// dimmed bar focuses its card before it acts, so nothing lands on the wrong
/// page. The bar's empty parts move the window, as the sidebar's strip does.
struct BrowserPageCardBar: View {
    // MARK: - Static Variables

    /// How a bar arrives and leaves as a page joins or leaves a split: down
    /// out of the card's top edge, and back up.
    static let transition = AnyTransition.move(edge: .top).combined(with: .opacity)

    // MARK: - Variables

    let page: BrowserPage?
    let tab: TabStateModel?
    let space: SpaceModel?
    let browser: BrowserStore
    let pages: BrowserPagePool
    let context: BrowserPageCardBarContext
    /// Whether this card is the one the window's commands act on.
    let isFocused: Bool
    /// Whether this card comes first in reading order, which is the one the
    /// window's buttons and the sidebar toggle stand over.
    let isLeadingCard: Bool

    /// A full-screen window has no corners and shows no buttons over its pages.
    @Environment(\.browserWindowCornerRadius) private var windowCornerRadius
    @Environment(\.layoutDirection) private var layoutDirection
    /// How wide this card's bar stands, which decides whether the leading
    /// card has room for the sidebar's toggle.
    @State private var barWidth = CGFloat.infinity

    var body: some View {
        BrowserPageBar(
            metrics: .pageCard,
            windowControlsClearance: windowControlsClearance,
            // Back, forward and their history menus focus this card before
            // they act, from the keyboard or accessibility as from a click.
            port: BrowserSidebarNavigationPort(
                page: { [page] in page },
                recordActivity: { [tab, focusCard = context.focusCard] in
                    if let tabID = tab?.id { focusCard(tabID) }
                },
                showHistory: context.showHistory),
            branding: space?.settings.look
        ) {
            BrowserPageCardAddressField(
                page: page,
                tab: tab,
                space: space,
                pages: pages,
                isUnderPalette: isFocused && context.opensFromOwnField && context.isPaletteShown(),
                fieldFrames: context.fieldFrames,
                activate: openLocation
            )
        } extensions: {
            if let space {
                BrowserEngineToolbarAccessory(page: page, space: space, browser: browser)
            }
        } leadingAccessory: {
            if showsSidebarToggle {
                Button(
                    context.sidebarToggleAction.title,
                    systemImage: context.sidebarOnRight ? "sidebar.right" : "sidebar.left",
                    action: context.toggleSidebar
                )
                .labelStyle(.iconOnly)
                .buttonStyle(CrestChromeButtonStyle(controlSize: BrowserPageBarMetrics.sidebarToggleSize))
                .help(context.sidebarToggleAction.title)
                .accessibilityIdentifier("page-card-sidebar-toggle")
            }
        }
        .opacity(isFocused ? 1 : CrestOpacity.unfocusedChrome)
        // An extension popup nothing was clicked for opens at the focused
        // card's tile or Site Controls, ahead of the window's own and the
        // other cards'.
        .environment(\.browserExtensionAnchorStanding, isFocused ? .focusedCard : .unfocusedCard)
        .modifier(SpaceColorScheme(branding: space?.settings.look))
        .background {
            // Only the bar's empty parts act as the title bar. Its controls
            // keep their own presses.
            BrowserWindowTitleBarSurface()
        }
        .background(barColor)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { barWidth = $0 }
        .accessibilityElement(children: .contain)
        // Each card's bar is named by its page, so VoiceOver tells them apart.
        .accessibilityLabel(Text("Page bar for \(spokenPageName)"))
        .accessibilityIdentifier(tab.map { "page-card-bar-\($0.id.uuidString)" } ?? "page-card-bar")
    }

    /// The Space's own color, as the windows show it now.
    private var barColor: Color {
        space?.settings.look.shown.backgroundColor.color ?? .clear
    }

    /// The room the leading card leaves for the window's buttons where they
    /// stand over it. AppKit keeps them in the window's leading corner in
    /// either direction, and while they stand over the cards the row starts
    /// one window frame in from that edge.
    private var windowControlsClearance: CGFloat {
        guard isLeadingCard, context.windowControlsOverLeadingCard, windowCornerRadius != nil else { return 0 }
        let frameLeading = BrowserChromeAppearance.device(windowCornerRadius: nil)
            .pageInsets(docked: context.isSidebarDocked, direction: layoutDirection).leading
        return max(
            0,
            BrowserPageBarMetrics.windowControlsClearance - frameLeading - BrowserPageBarMetrics.pageCard.leadingPadding
        )
    }

    /// The leading card carries the sidebar's toggle while the sidebar is not
    /// docked, so a hidden sidebar is a click away, as long as the card has
    /// room for it beside the window's buttons, back and forward, and the
    /// field at its narrowest. A narrower card leaves the sidebar to the View
    /// menu and the window's edge.
    private var showsSidebarToggle: Bool {
        isLeadingCard && !context.isSidebarDocked && barWidth >= widthForSidebarToggle
    }

    private var widthForSidebarToggle: CGFloat {
        let metrics = BrowserPageBarMetrics.pageCard
        return metrics.leadingPadding + windowControlsClearance + BrowserPageBarMetrics.sidebarToggleSize.width
            + metrics.spacing + BrowserPageBarNavigation.width + metrics.spacing + metrics.fieldMinimumWidth
            + metrics.trailingPadding
    }

    /// The page this bar belongs to, as VoiceOver names it: its title, or its
    /// address while it has none.
    private var spokenPageName: String {
        if let title = page?.live.title, !title.isEmpty { return title }
        return address
    }

    /// The page's address, or the tab's while it has no page.
    private var address: String {
        page?.live.displayURL?.absoluteString ?? tab?.url ?? ""
    }

    // MARK: - Actions - Address

    /// Focuses this card if another has focus, then opens the window's palette
    /// over this card's field, starting at its address.
    ///
    /// The palette grows out of whichever card has focus, so where focus
    /// moves to this card the palette opens a turn later, once the field it
    /// grows from has followed.
    private func openLocation() {
        let address = address
        guard !isFocused, let tabID = tab?.id else {
            context.chrome.openLocation(address)
            return
        }
        context.focusCard(tabID)
        guard context.opensFromOwnField else {
            context.chrome.openLocation(address)
            return
        }
        let chrome = context.chrome
        Task { @MainActor in chrome.openLocation(address) }
    }
}
