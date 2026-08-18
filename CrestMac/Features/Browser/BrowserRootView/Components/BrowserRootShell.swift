import SwiftUI

struct BrowserRootShell: View, BrowserChromeAnimating {
    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let shortcuts: BrowserShortcutStore?
    @Binding var storedSidebarWidth: Double
    let windowTransparencyIsEnabled: Bool
    let windowTransparencyStrength: Double
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var sidebarSurfaceNamespace

    var body: some View {
        ZStack(alignment: .leading) {
            BrowserRootBackdrop(
                space: model.browser.selectedSpace,
                transparencyIsEnabled: windowTransparencyIsEnabled,
                transparencyStrength: windowTransparencyStrength,
                isWindowFocused: model.isWindowFocused
            )

            HStack(spacing: 0) {
                BrowserRootDockedSidebarLayer(
                    presentation: model.sidebarPresentation,
                    width: model.sidebarWidth,
                    reduceMotion: reduceMotion,
                    morphsWithFloatingSidebar: model.isSidebarMorphing,
                    namespace: sidebarSurfaceNamespace,
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
                // A drag reshapes the sidebar — the gap the lifted row leaves,
                // its neighbours stepping aside, the insertion line — and
                // siblings of an `HStack` paint in order, so without this the
                // page surface would paint over the sidebar's own edge while
                // that is happening. It settles the order between SwiftUI
                // siblings only: the page's web view is an AppKit subtree and
                // outranks any of them, which is why the travelling preview is
                // drawn by `BrowserRootDragPreviewLayer` instead, for the whole
                // lift.
                .zIndex(
                    model.browser.sidebarReorderState.isDragging
                        ? BrowserRootMetrics.draggedSidebarZIndex
                        : 0
                )

                BrowserRootPageSurface(
                    model: model,
                    tabPromotionNamespace: tabPromotionNamespace
                )
            }
            .allowsHitTesting(!model.chrome.isCommandPalettePresented)
            .accessibilityHidden(model.chrome.isCommandPalettePresented)

            BrowserRootFloatingSidebarLayer(
                presentation: model.sidebarPresentation,
                width: model.sidebarWidth,
                space: model.browser.selectedSpace,
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency,
                morphsWithDockedSidebar: model.isSidebarMorphing,
                namespace: sidebarSurfaceNamespace,
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
            .allowsHitTesting(!model.chrome.isCommandPalettePresented)
            .accessibilityHidden(model.chrome.isCommandPalettePresented)

            BrowserRootShellControls(
                model: model,
                storedSidebarWidth: $storedSidebarWidth
            )
            .allowsHitTesting(!model.chrome.isCommandPalettePresented)
            .accessibilityHidden(model.chrome.isCommandPalettePresented)

            BrowserRootUtilityFanLayer(model: model)
                .zIndex(BrowserRootMetrics.utilityFanZIndex)

            BrowserRootDragPreviewLayer(
                model: model,
                reduceMotion: reduceMotion
            )

            BrowserNativeWindowControlsBridge(
                isVisible: model.sidebarPresentation.showsWindowControls
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            BrowserWindowTransparencyBridge(
                isEnabled: windowTransparencyIsEnabled && !reduceTransparency,
                isWindowFocused: model.isWindowFocusedBinding
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            BrowserRootCommandPaletteLayer(
                model: model,
                shortcuts: shortcuts,
                commandSurfaceNamespace: commandSurfaceNamespace
            )

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
        .animation(
            chromeAnimation(CrestMotion.sidebarMorph),
            value: model.chrome.columnVisibility
        )
        .animation(
            chromeAnimation(
                model.isSidebarMorphing
                    ? CrestMotion.sidebarMorph
                    : CrestMotion.floatingPane
            ),
            value: model.isFloatingSidebarPresented
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
        .background {
            BrowserSidebarAuxiliaryMouseMonitor(
                perform: model.handleAuxiliaryMouseAction
            )
        }
    }

}
