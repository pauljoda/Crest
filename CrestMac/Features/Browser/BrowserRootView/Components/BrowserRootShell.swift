import SwiftUI

struct BrowserRootShell: View, BrowserChromeAnimating {
    // MARK: - Variables

    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let shortcuts: BrowserShortcutStore?
    @Binding var storedSidebarWidth: Double
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.browserRootStylesWindow) private var stylesWindow
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var downloadFeedback = BrowserMacDownloadFeedbackState()
    @State private var spacePagerPresentation = SpacePagerPresentation()
    @AppStorage(SidebarFullscreenRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue

    /// The shell places the sidebar; the page frames under it read the rest.
    private var sidebarOnRight: Bool { BrowserDeviceAppearanceStore.shared.sidebarOnRight }
    private var sidebarEdge: HorizontalEdge {
        BrowserChromeAppearance.sidebarEdge(onRight: sidebarOnRight, in: layoutDirection)
    }

    // MARK: - Actions - Presentation

    var body: some View {
        ZStack(alignment: .leading) {
            BrowserRootFullscreenContent(
                pages: model.pages,
                revealsSidebar: revealsSidebarInFullscreen,
                sidebarEdge: sidebarEdge
            ) {
                standardContent
            } sidebar: {
                sidebarSurface
                    .modifier(BrowserCommandPaletteBackgroundGuard(chrome: model.chrome))
            } controls: {
                shellControls
                    .modifier(BrowserCommandPaletteBackgroundGuard(chrome: model.chrome))
            }
            .animation(chromeAnimation(CrestMotion.collection), value: sidebarOnRight)
            .animation(
                model.sidebarAnimation(
                    model.isSidebarApproachingDock
                        ? CrestMotion.sidebarDockAttachment
                        : CrestMotion.sidebarMorph,
                    reduceMotion: reduceMotion
                ),
                value: model.chrome.columnVisibility
            )
            .animation(
                model.sidebarAnimation(
                    model.isSidebarApproachingDock
                        ? CrestMotion.sidebarDockAttachment
                        : model.isSidebarMorphing
                            ? CrestMotion.sidebarMorph
                            : CrestMotion.floatingPane,
                    reduceMotion: reduceMotion
                ),
                value: model.isFloatingSidebarPresented
            )
            .animation(
                model.sidebarAnimation(CrestMotion.sidebarDockApproach, reduceMotion: reduceMotion),
                value: model.isSidebarApproachingDock
            )

            // Window focus gates the edge reveal in the shell and over a page
            // in full screen alike, so it is followed whichever shows.
            BrowserWindowFocusBridge(isWindowFocused: model.isWindowFocusedBinding)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // The window's chrome belongs to the window, not to the chrome a
            // fullscreen page hides: taking it down would restore the window's
            // style while AppKit is carrying it into fullscreen.
            // With the address bar on top the buttons stay at the window's top
            // left in every sidebar state, over the window's address bar or the
            // leading card's when the sidebar does not hold them. They cross
            // the window on the sidebar's own curve when it changes sides.
            if stylesWindow {
                BrowserNativeWindowControlsHost(model: model, sidebarOnRight: sidebarOnRight)
                    .animation(chromeAnimation(CrestMotion.collection), value: sidebarOnRight)
            }

            // A held Most Recent Tab shortcut shows the recent tabs over the
            // window, fullscreen page or not.
            BrowserRecentTabsLayer(chrome: model.chrome)

            // The card of the tab the sidebar is rested on shows beside the
            // sidebar and over the page, a floating sidebar's too.
            BrowserMacTabPreviewLayer(model: model)
        }
        // Notices stand in the top trailing corner of the page, below the
        // bars along its top, and over a fullscreen page too, so one posted
        // there is never lost.
        .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
            BrowserRootNoticeOverlayHost(model: model, anchor: anchor)
        }
        .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
            GeometryReader { proxy in
                let rect = anchor.map { proxy[$0] } ?? CGRect(origin: .zero, size: proxy.size)
                BrowserRootCommandPaletteLayer(
                    model: model,
                    shortcuts: shortcuts,
                    spaceSettingsPresentation: spaceSettingsPresentation,
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    contentInsets: BrowserChromeAppearance.contentInsets(
                        for: rect, in: proxy.size, direction: layoutDirection
                    ),
                    fieldOrigin: proxy.frame(in: .global).origin
                )
            }
        }
        // One per-window host answers for every row and tile in this shell,
        // so the sidebar reads it from here rather than being handed a value
        // per tab through the tree between them.
        .environment(downloadFeedback)
        .environment(model.extensionTileLift)
        .environment(\.spacePagerPresentation, spacePagerPresentation)
        .onChange(
            of: model.chrome.utilityPresentation.isSidebarInteractionActive
        ) { _, isActive in
            model.sidebarInteractionChanged(
                isActive,
                reduceMotion: reduceMotion
            )
        }
        .modifier(BrowserRootPermissionObserver(model: model, reduceMotion: reduceMotion))
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: revealsSidebarOverFullscreenPage, initial: true) { _, reveals in
            model.fullscreenSidebarRevealChanged(reveals)
        }
        .onChange(of: model.chrome.spaceShortcutSidebarRequest) {
            model.revealSidebarForSpaceShortcut(reduceMotion: reduceMotion)
        }
        .onChange(of: transientBrowsing.orphanedPeeks(in: model.browser), initial: true) {
            transientBrowsing.reconcilePeeks(in: model.browser)
        }
        .onChange(of: transientBrowsing.peekRequests, initial: true) {
            model.pages.retainPeekPages(for: transientBrowsing.peekRequests)
        }
    }

    private var standardContent: some View {
        ZStack(alignment: .leading) {
            BrowserRootBackdrop(
                space: model.browser.shownSpace,
                spaces: model.browser.availableSpaces
            )

            BrowserSidebarPageLayout(
                presentation: model.sidebarPresentation,
                width: model.sidebarWidth,
                edge: sidebarEdge,
                isApproachingDock: model.isSidebarApproachingDock
            ) {
                BrowserSpacePageSurface(
                    model: model, transientBrowsing: transientBrowsing,
                    tabPromotionNamespace: tabPromotionNamespace, shortcuts: shortcuts
                )
                .clipped()
            } sidebar: {
                sidebarSurface
            } controls: {
                shellControls
            }
            // Over the page and the sidebar alike, so the field it shares with
            // the sidebar is never hidden under either while it moves between
            // them.
            .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
                BrowserWindowAddressBarLayer(
                    model: model, transientBrowsing: transientBrowsing, page: anchor,
                    commandSurfaceNamespace: commandSurfaceNamespace)
            }
            .modifier(BrowserCommandPaletteBackgroundGuard(chrome: model.chrome))

            BrowserRootUtilityFanLayer(model: model, sidebarOnRight: sidebarOnRight)
                .zIndex(BrowserRootMetrics.utilityFanZIndex)

            BrowserMacDownloadFeedbackLayer(model: model, feedback: downloadFeedback)
                .zIndex(BrowserRootMetrics.utilityFanZIndex + 1)

            BrowserRootDragPreviewLayer(
                model: model,
                reduceMotion: reduceMotion
            )
        }
    }

    private var revealsSidebarOverFullscreenPage: Bool {
        revealsSidebarInFullscreen && model.pages.activePage?.isContentFullscreen == true
    }

    private var sidebarSurface: some View {
        BrowserRootSidebarSurfaceLayer(
            presentation: model.sidebarPresentation,
            width: model.sidebarWidth,
            edge: sidebarEdge,
            space: model.browser.shownSpace,
            reduceTransparency: reduceTransparency,
            spaces: model.browser.availableSpaces,
            isRevealedByPointer: model.isFloatingSidebarRevealedByPointer,
            isResizing: model.sidebarWidthTransaction.isResizing,
            hoverChanged: {
                model.sidebarSurfaceHoverChanged(
                    $0,
                    reduceMotion: reduceMotion
                )
            }
        ) {
            BrowserRootSidebarContent(
                model: model,
                spaceSettingsPresentation: spaceSettingsPresentation,
                commandSurfaceNamespace: commandSurfaceNamespace,
                tabPromotionNamespace: tabPromotionNamespace
            )
        }
        .background {
            BrowserSidebarPointerNavigationHost(model: model)
        }
        // A floating sidebar keeps Split View from handing the pointer to
        // the card beneath it.
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            model.splitCoveringChrome.sidebarFrame = $0
        }
    }

    private var shellControls: some View {
        BrowserRootShellControls(
            model: model, storedSidebarWidth: $storedSidebarWidth, sidebarEdge: sidebarEdge)
    }
}

/// Tab selection is observed here so the ordinary shell's inputs stay stable
/// when only the page occupying it changes.
///
/// A page alone in full screen keeps the sidebar's hover area when the person
/// asked for it, and the sidebar floats over the page without moving it.
private struct BrowserRootFullscreenContent<Content: View, Sidebar: View, Controls: View>: View {
    let pages: BrowserPagePool
    let revealsSidebar: Bool
    let sidebarEdge: HorizontalEdge
    @ViewBuilder let content: Content
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let controls: Controls

    var body: some View {
        if let page = pages.activePage, page.isContentFullscreen {
            ZStack(alignment: .leading) {
                BrowserPlatformWebView(
                    page: page,
                    isPageActive: true,
                    focusRestorationGate: .suppressed
                )
                .environment(\.browserPagePresentationWindowID, pages.windowID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)

                if revealsSidebar {
                    sidebar.frame(maxWidth: .infinity, alignment: edgeAlignment)
                    controls.frame(maxWidth: .infinity, alignment: edgeAlignment)
                }
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }

    private var edgeAlignment: Alignment {
        sidebarEdge == .leading ? .leading : .trailing
    }
}

private struct BrowserRootPermissionObserver: ViewModifier {
    // MARK: - Types

    /// The active page's waiting request, and whether the sidebar's field is
    /// where it asks.
    private struct Prompt: Equatable {
        let requestID: UUID?
        let asksInSidebar: Bool
    }

    // MARK: - Variables

    let model: BrowserRootModel
    let reduceMotion: Bool

    /// A page card's bar asks on its own card, as a split's cards always do,
    /// so the sidebar comes out only while its field is where the request
    /// asks: when a request arrives there, or when a request still waiting
    /// moves there, as the address bar returns to the sidebar or a split ends.
    func body(content: Content) -> some View {
        content.onChange(of: prompt) { _, prompt in
            if prompt.requestID != nil, prompt.asksInSidebar {
                model.presentFloatingSidebar(reduceMotion: reduceMotion)
            }
        }
    }

    private var prompt: Prompt {
        Prompt(
            requestID: model.pages.activePage?.sitePermissionRequests.current?.id,
            asksInSidebar: !model.showsPageCardBars && !model.presentsSplitBars)
    }
}

/// Reads `isCommandPalettePresented` in a leaf view so toggling the command
/// palette never invalidates `BrowserRootShell.body`.
private struct BrowserSidebarPointerNavigationHost: View {
    let model: BrowserRootModel

    var body: some View {
        BrowserSidebarPointerNavigation(
            isSidebarVisible:
                model.sidebarPresentation.showsSidebar
                && !model.chrome.isCommandPalettePresented,
            perform: model.handleAuxiliaryMouseAction,
            navigationTargets: { [pages = model.pages] in pages.livePages },
            activeTarget: { [pages = model.pages] in pages.activePage }
        )
    }
}

/// Reads `showsPageCardBars` in a leaf view so swapping address bar placement
/// never invalidates `BrowserRootShell.body`.
private struct BrowserNativeWindowControlsHost: View {
    let model: BrowserRootModel
    let sidebarOnRight: Bool

    var body: some View {
        BrowserNativeWindowControlsBridge(
            isVisible: model.sidebarPresentation.showsWindowControls || model.showsPageCardBars,
            sidebarOnRight: sidebarOnRight && !model.showsPageCardBars,
            sidebarWidth: model.sidebarWidth
        )
        .frame(maxWidth: .infinity)
        .frame(height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Computes notice padding in a leaf view so address-bar placement changes do
/// not rebuild `BrowserRootShell.body`.
private struct BrowserRootNoticeOverlayHost: View {
    let model: BrowserRootModel
    let anchor: Anchor<CGRect>?
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { proxy in
            BrowserNoticeLayer(notices: model.chrome.notices)
                .padding(noticeArea(page: anchor.map { proxy[$0] }, in: proxy.size))
        }
    }

    private func noticeArea(page: CGRect?, in size: CGSize) -> EdgeInsets {
        guard let page, model.pages.activePage?.isContentFullscreen != true else { return EdgeInsets() }
        var insets = BrowserChromeAppearance.contentInsets(for: page, in: size, direction: layoutDirection)
        if model.showsPageCardBars || model.presentsSplitBars {
            insets.top += BrowserPageBarMetrics.topSectionHeight
        }
        return insets
    }
}

/// Observes `isCommandPalettePresented` in a leaf modifier so toggling the
/// command palette never invalidates `BrowserRootShell.body`.
private struct BrowserCommandPaletteBackgroundGuard: ViewModifier {
    let chrome: BrowserChromeState

    func body(content: Content) -> some View {
        let isPresented = chrome.isCommandPalettePresented
        content
            .allowsHitTesting(!isPresented)
            .accessibilityHidden(isPresented)
    }
}
