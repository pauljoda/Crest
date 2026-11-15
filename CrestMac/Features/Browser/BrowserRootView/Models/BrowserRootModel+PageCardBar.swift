import SwiftUI

// MARK: - Page Card Bar

extension BrowserRootModel {
    /// Whether the address bar is on top, as the device's appearance places
    /// it.
    var showsPageCardBars: Bool {
        BrowserDeviceAppearanceStore.shared.addressBarPlacement.showsBarInPageCards
    }

    /// Whether the window shows a split, whose cards carry bars of their own
    /// in either placement, as a Quick Window does.
    var presentsSplitBars: Bool {
        guard let space = browser.shownSpace else { return false }
        return browser.cards(in: space).count > 1
    }

    /// Whether the window's own address bar stands along the top of its
    /// page: while the address bar is on top, unless a split's cards carry
    /// theirs.
    var showsWindowTopBar: Bool {
        showsPageCardBars && !presentsSplitBars
    }

    /// Whether the window's own buttons stand over the top of the page in
    /// `direction`. With the address bar on top they stay in the window's
    /// leading corner, where AppKit puts them, so they stand over the page
    /// unless a sidebar docked on that edge holds them. In the sidebar
    /// placement they stay in the sidebar's strip, or hide with it.
    func windowControlsStandOverPage(in direction: LayoutDirection) -> Bool {
        guard showsPageCardBars else { return false }
        let sidebarEdge = BrowserChromeAppearance.sidebarEdge(
            onRight: BrowserDeviceAppearanceStore.shared.sidebarOnRight, in: direction)
        return !(sidebarPresentation.reservesSidebarWidth && sidebarEdge == .leading)
    }

    /// What every card's bar in a split needs from this window.
    func pageCardBarContext(reduceMotion: Bool, layoutDirection: LayoutDirection) -> BrowserPageCardBarContext {
        let presentation = sidebarPresentation
        let sidebarOnRight = BrowserDeviceAppearanceStore.shared.sidebarOnRight
        return BrowserPageCardBarContext(
            chrome: chrome,
            fieldFrames: pageBarFieldFrames,
            windowControlsOverLeadingCard: windowControlsStandOverPage(in: layoutDirection),
            opensFromOwnField: showsPageCardBars,
            isSidebarDocked: presentation.reservesSidebarWidth,
            sidebarOnRight: sidebarOnRight,
            sidebarToggleAction: presentation.sidebarToggleAction,
            isPaletteShown: { [weak self] in self?.isCommandPaletteShown == true },
            toggleSidebar: { [weak self] in self?.toggleSidebar(reduceMotion: reduceMotion) },
            focusCard: { [weak self] in self?.focusSplitCard($0) },
            showHistory: { [weak self] in self?.chrome.presentUtility(.history) }
        )
    }

    /// The field the window's palette drops out of while the address bar is
    /// on top, in window coordinates: the window's own along the top of a
    /// lone page, or the focused card's in a split.
    var paletteFieldFrame: CGRect? {
        guard showsPageCardBars else { return nil }
        guard presentsSplitBars else { return pageBarFieldFrames.windowFrame }
        return browser.shownTab.flatMap { pageBarFieldFrames.frame(for: $0.id) }
    }

    /// Whether the field the palette drops out of is a split card's, which
    /// lives in its card's own hosting view, out of reach of the palette's
    /// namespace.
    var paletteFieldIsCard: Bool {
        showsPageCardBars && presentsSplitBars
    }
}
