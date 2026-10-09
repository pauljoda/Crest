import SwiftUI

struct BrowserRootShell: View, BrowserChromeAnimating {
    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let shortcuts: BrowserShortcutStore?
    @Binding var storedSidebarWidth: Double
    var appearance = BrowserChromeAppearance()
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var downloadFeedback = BrowserMacDownloadFeedbackState()
    @State private var spacePagerPresentation = SpacePagerPresentation()

    private var sidebarEdge: HorizontalEdge { appearance.sidebarEdge(in: layoutDirection) }

    var body: some View {
        ZStack(alignment: .leading) {
            BrowserRootFullscreenContent(pages: model.pages) {
                standardContent
            }

            // The window's chrome belongs to the window, not to the chrome a
            // fullscreen page hides: taking it down would restore the window's
            // style while AppKit is carrying it into fullscreen.
            BrowserNativeWindowControlsBridge(
                isVisible: model.sidebarPresentation.showsWindowControls,
                sidebarPosition: appearance.sidebarOnRight ? 1 : 0,
                sidebarWidth: model.sidebarWidth
            )
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
            GeometryReader { proxy in
                let rect = anchor.map { proxy[$0] } ?? CGRect(origin: .zero, size: proxy.size)
                BrowserRootCommandPaletteLayer(
                    model: model,
                    shortcuts: shortcuts,
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    contentInsets: BrowserChromeAppearance.contentInsets(
                        for: rect, in: proxy.size, direction: layoutDirection
                    )
                )
            }
        }
        // One per-window host answers for every row and tile in this shell,
        // so the sidebar reads it from here rather than being handed a value
        // per tab through the tree between them.
        .environment(downloadFeedback)
        .environment(\.browserChromeAppearance, appearance)
        .environment(\.spacePagerPresentation, spacePagerPresentation)
        .environment(
            \.browserWebFocusRestorationGate,
            BrowserWebFocusRestorationGate(
                browserChromeOwnsFocus:
                    !model.isWindowFocused
                    || model.isAddressEditing
                    || model.chrome.isCommandPalettePresented,
                pageChromeOwnsFocus: false
            )
        )
        .animation(chromeAnimation(CrestMotion.collection), value: appearance.sidebarOnRight)
        .animation(
            chromeAnimation(
                model.isSidebarApproachingDock
                    ? CrestMotion.sidebarDockAttachment
                    : CrestMotion.sidebarMorph
            ),
            value: model.chrome.columnVisibility
        )
        .animation(
            chromeAnimation(
                model.isSidebarApproachingDock
                    ? CrestMotion.sidebarDockAttachment
                    : model.isSidebarMorphing
                        ? CrestMotion.sidebarMorph
                        : CrestMotion.floatingPane
            ),
            value: model.isFloatingSidebarPresented
        )
        .animation(
            chromeAnimation(CrestMotion.sidebarDockApproach),
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
                spaces: BrowserSidebarAccessPolicy.availableSpaces(in: model.browser)
            )

            BrowserSidebarPageLayout(
                presentation: model.sidebarPresentation,
                width: model.sidebarWidth,
                edge: sidebarEdge,
                isApproachingDock: model.isSidebarApproachingDock
            ) {
                BrowserSpacePageSurface(
                    model: model, transientBrowsing: transientBrowsing,
                    tabPromotionNamespace: tabPromotionNamespace, shortcuts: shortcuts, appearance: appearance
                )
                .clipped()
            } sidebar: {
                BrowserRootSidebarSurfaceLayer(
                    presentation: model.sidebarPresentation,
                    width: model.sidebarWidth,
                    edge: sidebarEdge,
                    space: model.browser.shownSpace,
                    reduceTransparency: reduceTransparency,
                    spaces: BrowserSidebarAccessPolicy.availableSpaces(in: model.browser),
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
            } controls: {
                BrowserRootShellControls(
                    model: model, storedSidebarWidth: $storedSidebarWidth, sidebarEdge: sidebarEdge)
            }
            .allowsHitTesting(!model.chrome.isCommandPalettePresented)
            .accessibilityHidden(model.chrome.isCommandPalettePresented)

            BrowserRootUtilityFanLayer(model: model, sidebarOnRight: appearance.sidebarOnRight)
                .zIndex(BrowserRootMetrics.utilityFanZIndex)

            BrowserMacDownloadFeedbackLayer(model: model, feedback: downloadFeedback)
                .zIndex(BrowserRootMetrics.utilityFanZIndex + 1)

            BrowserRootDragPreviewLayer(
                model: model,
                reduceMotion: reduceMotion
            )

            BrowserWindowFocusBridge(isWindowFocused: model.isWindowFocusedBinding)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if let notice = model.visibleNotice {
                BrowserNoticeView(notice: notice)
                    .id(notice)
            }
        }
    }

}

/// Tab selection is observed here so the ordinary shell's inputs stay stable
/// when only the page occupying it changes.
private struct BrowserRootFullscreenContent<Content: View>: View {
    let pages: BrowserPagePool
    @ViewBuilder let content: Content

    var body: some View {
        if let page = pages.activePage, page.isContentFullscreen {
            BrowserPlatformWebView(
                page: page,
                isPageActive: true,
                focusRestorationGate: .suppressed
            )
            .environment(\.browserPagePresentationWindowID, pages.windowID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea()
        } else {
            content
        }
    }
}

private struct BrowserRootPermissionObserver: ViewModifier {
    let model: BrowserRootModel
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content.onChange(of: model.pages.activePage?.sitePermissionRequests.current?.id) {
            if model.pages.activePage?.sitePermissionRequests.current != nil {
                model.presentFloatingSidebar(reduceMotion: reduceMotion)
            }
        }
    }
}
