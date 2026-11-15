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
                    .allowsHitTesting(!model.chrome.isCommandPalettePresented)
                    .accessibilityHidden(model.chrome.isCommandPalettePresented)
            } controls: {
                shellControls
                    .allowsHitTesting(!model.chrome.isCommandPalettePresented)
                    .accessibilityHidden(model.chrome.isCommandPalettePresented)
            }

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
            // leading card's when the sidebar does not hold them.
            BrowserNativeWindowControlsBridge(
                isVisible: model.sidebarPresentation.showsWindowControls || model.showsPageCardBars,
                sidebarOnRight: sidebarOnRight && !model.showsPageCardBars,
                sidebarWidth: model.sidebarWidth
            )
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // A held Most Recent Tab shortcut shows the recent tabs over the
            // window, fullscreen page or not.
            BrowserRecentTabsLayer(chrome: model.chrome)

            // The card of the tab the sidebar is rested on shows beside the
            // sidebar and over the page, a floating sidebar's too.
            BrowserMacTabPreviewLayer(model: model)

            // Notices show over a fullscreen page too, so one posted there
            // is never lost.
            BrowserNoticeLayer(notices: model.chrome.notices)
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
        .animation(chromeAnimation(CrestMotion.collection), value: sidebarOnRight)
        // The address bar changing place carries the window's field between
        // the sidebar and the top of the page.
        .animation(CrestMotion.chrome.unlessReducingMotion(reduceMotion), value: model.showsPageCardBars)
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
        .animation(
            BrowserCommandSurfaceMorph.commandPaletteAnimation(reduceMotion: reduceMotion),
            value: model.isCommandPaletteShown
        )
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
            .allowsHitTesting(!model.chrome.isCommandPalettePresented)
            .accessibilityHidden(model.chrome.isCommandPalettePresented)

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
            BrowserSidebarPointerNavigation(
                isSidebarVisible:
                    model.sidebarPresentation.showsSidebar
                    && !model.chrome.isCommandPalettePresented,
                perform: model.handleAuxiliaryMouseAction,
                navigationTargets: { [pages = model.pages] in pages.livePages },
                activeTarget: { [pages = model.pages] in pages.activePage }
            )
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
