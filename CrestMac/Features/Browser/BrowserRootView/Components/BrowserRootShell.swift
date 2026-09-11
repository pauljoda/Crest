import SwiftUI

struct BrowserRootShell: View, BrowserChromeAnimating {
    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let shortcuts: BrowserShortcutStore?
    @Binding var storedSidebarWidth: Double
    var appearance = BrowserChromeAppearance()
    let windowTransparencyIsEnabled: Bool
    let windowTransparencyStrength: Double
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(BrowserExtensionSidebarStore.self) private var extensionSidebar: BrowserExtensionSidebarStore?
    @State private var downloadFeedback = BrowserMacDownloadFeedbackState()
    @State private var spacePagerPresentation = SpacePagerPresentation()

    private var sidebarEdge: HorizontalEdge { appearance.sidebarEdge(in: layoutDirection) }

    var body: some View {
        ZStack(alignment: .leading) {
            BrowserRootBackdrop(
                space: model.browser.selectedSpace,
                spaces: BrowserSidebarAccessPolicy.availableSpaces(in: model.browser),
                transparencyIsEnabled: windowTransparencyIsEnabled,
                transparencyStrength: windowTransparencyStrength,
                isWindowFocused: model.isWindowFocused
            )

            BrowserSidebarPageLayout(
                presentation: model.sidebarPresentation,
                width: model.sidebarWidth,
                edge: sidebarEdge,
                isApproachingDock: model.isSidebarApproachingDock
            ) {
                BrowserSpacePageSurface(
                    model: model, tabPromotionNamespace: tabPromotionNamespace, appearance: appearance)
            } sidebar: {
                BrowserRootSidebarSurfaceLayer(
                    presentation: model.sidebarPresentation,
                    width: model.sidebarWidth,
                    edge: sidebarEdge,
                    space: model.browser.selectedSpace,
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
                        sidebarOnRight: appearance.sidebarOnRight,
                        spaceSettingsPresentation: spaceSettingsPresentation,
                        commandSurfaceNamespace: commandSurfaceNamespace,
                        tabPromotionNamespace: tabPromotionNamespace
                    )
                }
                .background {
                    BrowserSidebarAuxiliaryMouseMonitor(
                        isSidebarVisible:
                            model.sidebarPresentation.showsSidebar
                            && !model.chrome.isCommandPalettePresented,
                        perform: model.handleAuxiliaryMouseAction
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

            BrowserNativeWindowControlsBridge(
                isVisible: model.sidebarPresentation.showsWindowControls,
                sidebarPosition: appearance.sidebarOnRight ? 1 : 0,
                sidebarWidth: model.sidebarWidth
            )
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            BrowserWindowTransparencyBridge(
                isEnabled: windowTransparencyIsEnabled && !reduceTransparency,
                isWindowFocused: model.isWindowFocusedBinding
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            BrowserRootPeekLayer(
                model: model,
                transientBrowsing: transientBrowsing
            )

            if model.isURLCopiedFeedbackVisible {
                BrowserURLCopyFeedbackView()
            }

            if let label = model.visiblePageZoomFeedbackLabel {
                BrowserPageZoomFeedbackView(label: label)
            }
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
            chromeAnimation(CrestMotion.pane),
            value: model.chrome.isCommandPalettePresented
        )
        .onChange(
            of: model.chrome.utilityPresentation.isSidebarInteractionActive
        ) { _, isActive in
            model.sidebarInteractionChanged(
                isActive,
                reduceMotion: reduceMotion
            )
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear { model.configureExtensionSidebar(extensionSidebar) }
        .onChange(of: model.extensionSidebar?.panel) { model.extensionSidebar?.reconcile() }
        .onDisappear { model.extensionSidebar?.release() }
    }

}
