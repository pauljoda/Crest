import CoreGraphics

/// Feature-specific chrome geometry; cross-feature hit targets come from `CrestLayout`.
enum MobileBrowserChromeLayout {
    static let compactToolbarSpacing: CGFloat = 8
    static let compactToolbarHorizontalPadding: CGFloat = 10
    static let compactToolbarVerticalPadding: CGFloat = 6
    static let compactToolbarSymbolSize: CGFloat = 16

    static let collapsedSidebarRevealWidth: CGFloat = 26
    static let collapsedSidebarGestureDistance: CGFloat = 10
    static let collapsedSidebarControlPadding: CGFloat = 10

    static let findItemSpacing: CGFloat = 6
    static let findLeadingPadding: CGFloat = 14
    static let findTrailingPadding: CGFloat = 4
    static let findStatusWidth: CGFloat = 24
    static let findButtonWidth: CGFloat = 40
    static let findShadowOpacity = 0.14
    static let findShadowRadius: CGFloat = 12
    static let findShadowOffset: CGFloat = 5
    static let regularFindMaximumWidth: CGFloat = 440
    static let compactFindHorizontalPadding: CGFloat = 10
    static let regularFindHorizontalPadding: CGFloat = 12
    static let regularFindTopPadding: CGFloat = 12
    static let compactFindToolbarGap: CGFloat = 14
    static let findFallbackBottomPadding: CGFloat = 12

    static let historyDividerHeight: CGFloat = 18
    static let historyDividerOpacity = 0.24
    static let historyCapsuleHorizontalPadding: CGFloat = 2

    static let regularStartPageSpacing: CGFloat = 28
    static let regularStartPagePadding: CGFloat = 40
    static let regularStartPageMaximumWidth: CGFloat = 820
    static let compactStartPageSpacing: CGFloat = 22
    static let compactStartPagePadding: CGFloat = 24
    static let compactStartPageMaximumWidth: CGFloat = 620
    static let startPageMarkSize: CGFloat = 48
    static let privateNoticeSpacing: CGFloat = 6
}

/// Geometry and timing owned by the mobile browser composition shell.
enum MobileBrowserRootLayout {
    static let defaultRegularSidebarWidth: CGFloat = 320
    static let resizeHandleOverlap: CGFloat = 8

    static let compactOverlayTopPadding: CGFloat = 12
    static let regularOverlayTopPadding: CGFloat = 18
    static let overlayScrimOpacity = 0.16
    static let overlayShadowOpacity = 0.24
    static let overlayShadowRadius: CGFloat = 18
    static let overlayShadowOffset: CGFloat = 5

    static let feedbackHorizontalPadding: CGFloat = 14
    static let feedbackHeight: CGFloat = 40
    static let feedbackShadowRadius: CGFloat = 16
    static let feedbackShadowOffset: CGFloat = 8
    static let feedbackVisibilityDuration: Duration = .seconds(1.4)

    static let paletteLayer: Double = 10
    static let feedbackLayer: Double = 30
    static let sidebarLayer: Double = 3
    static let utilityLayer: Double = 8

    /// Gives detached sidebar controls the same breathing room as the card's
    /// other floating chrome without moving their docked-window alignment.
    static let floatingSidebarBottomChromeInset: CGFloat = 6
}

enum MobileBrowserRootPreferences {
    /// Keep the existing key so current installs retain their preferred width.
    /// The value now applies to every expanded iOS layout, not only iPad.
    static let adaptiveSidebarWidthKey = "crest.sidebar.width.ipad"
}

enum MobileCollapsedSidebarFullscreenPreference {
    static let key = "crest.sidebar.collapsed.fullscreen.mobile"
}

enum MobileBrowserPresentationPolicy {
    static let expandedLayoutMinimumWidth: CGFloat = 600

    static func resolve(
        availableWidth: CGFloat
    ) -> MobileBrowserPresentation {
        if availableWidth >= expandedLayoutMinimumWidth {
            return .regular
        }
        return .compact
    }
}

enum MobileSidebarPageFramePolicy {
    static func usesBorderlessFrame(
        preferenceIsEnabled: Bool,
        sidebarPresentation: BrowserSidebarPresentation,
        presentsSplitView: Bool,
        browserPresentation: MobileBrowserPresentation
    ) -> Bool {
        guard !presentsSplitView else { return false }
        if browserPresentation == .compact,
            sidebarPresentation == .docked
        {
            return true
        }
        return preferenceIsEnabled && sidebarPresentation != .docked
    }

    static func showsCompactToolbar(
        sidebarPresentation: BrowserSidebarPresentation,
        presentsSplitView: Bool
    ) -> Bool {
        presentsSplitView || sidebarPresentation == .docked
    }
}

enum MobileSidebarTabSelectionPolicy {
    static func dismissesSidebar(
        browserPresentation: MobileBrowserPresentation,
        sidebarPresentation: BrowserSidebarPresentation
    ) -> Bool {
        browserPresentation == .compact
            && sidebarPresentation == .floating
    }
}

enum MobileKeyboardLayoutPolicy {
    static let floatingKeyboardMaximumWidthRatio: CGFloat = 0.85

    static func isFloating(
        keyboardFrame: CGRect,
        availableSize: CGSize
    ) -> Bool {
        guard !keyboardFrame.isNull,
            !keyboardFrame.isEmpty,
            availableSize.width > 0
        else { return false }
        return keyboardFrame.width
            < availableSize.width * floatingKeyboardMaximumWidthRatio
    }
}

enum MobileCompactDomainChipLayout {
    static let visibleHeight: CGFloat = 36
    static let minimumHitTarget = CrestLayout.minimumHitTarget
    static let horizontalPadding: CGFloat = 14
    static let outerHorizontalPadding: CGFloat = 12
}

enum MobileCompactPageChromePolicy {
    static let usesPageThemeBackdrop = true
    static let drawsToolbarBackground = false
    static let extendsWebContentBehindToolbar = true
}

enum MobileCompactTabViewerLayout {
    static let showsTopAddressBar = false
}

enum MobileFullTabPresentationPolicy {
    static let allowsInteractiveDismissal = false
}
