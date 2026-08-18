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

    var body: some View {
        ZStack(alignment: .leading) {
            BrowserRootBackdrop(
                space: model.browser.selectedSpace,
                transparencyIsEnabled: windowTransparencyIsEnabled,
                transparencyStrength: windowTransparencyStrength,
                isWindowFocused: model.isWindowFocused
            )

            HStack(spacing: 0) {
                BrowserRootSidebarLayoutReservation(
                    presentation: model.sidebarPresentation,
                    width: model.sidebarWidth,
                    isApproachingDock: model.isSidebarApproachingDock
                )

                BrowserRootPageSurface(
                    model: model,
                    tabPromotionNamespace: tabPromotionNamespace
                )
            }
            .allowsHitTesting(!model.chrome.isCommandPalettePresented)
            .accessibilityHidden(model.chrome.isCommandPalettePresented)

            // One content tree owns the sidebar in every presentation. Card
            // styling and layout move around it, so docking never recreates
            // the native space pager or replays its initial scroll position.
            BrowserRootSidebarSurfaceLayer(
                presentation: model.sidebarPresentation,
                width: model.sidebarWidth,
                space: model.browser.selectedSpace,
                reduceTransparency: reduceTransparency,
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
        .background {
            BrowserSidebarAuxiliaryMouseMonitor(
                perform: model.handleAuxiliaryMouseAction
            )
        }
    }

}
