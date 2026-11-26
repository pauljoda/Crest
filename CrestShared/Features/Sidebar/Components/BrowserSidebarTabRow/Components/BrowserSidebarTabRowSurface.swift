import SwiftUI
import UniformTypeIdentifiers

/// Everything wrapped around a tab row's content: its band, its selection and
/// hover treatment, and every gesture the row answers.
///
/// Two things about this chain are load-bearing and invisible in the code.
///
/// **The lift is armed before the menu.** `browserTabDraggable` must stay above
/// `contextMenu`. On a touch shell the lift *is* drag-and-drop —
/// `UIContextMenuInteraction` cancels any gesture that competes with it, so
/// drag-and-drop is the only path the system arbitrates against a menu — and the
/// row is the view that carries both. Move the menu under the drag source and
/// holding a row raises the menu with nothing left to pull.
///
/// **A row claims at most one promotion anchor.** The pairing below is an
/// either/or: `browserTabPromotionDestination` for a shell that grows a surface
/// out of the row through matched geometry, `BrowserPlatformTabPromotionSource`
/// for one that pushes a page with the system's navigation zoom. Both anchor the
/// same identity, and both are presentation transforms over the exact view the
/// drag interaction lifts. Two of them, or one with no partner to pair with, and
/// the lift stops starting — which is what
/// `BrowserInteractionCapabilities.usesMatchedGeometryPromotionDestination` and
/// `BrowserInteractionCapabilities.pairsRowWithPromotedSurface` exist to keep
/// from happening.
struct BrowserSidebarTabRowSurface: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserSidebarTabRowConfiguration
    let interaction: BrowserSidebarTabRowInteractionContext
    var statusMarks: [BrowserTabStatusMark]? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.browserSidebarRowJoinsReorder) private var joinsReorder
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .frame(
                minHeight: minHeight,
                maxHeight: configuration.metrics.fillsRowHeight ? minHeight : nil
            )
            .contentShape(.rect)
            .modifier(
                BrowserSidebarTabRowAppearance(
                    configuration: configuration,
                    isHovering: interaction.isHovering,
                    statusMarks: statusMarks
                )
            )
            .padding(
                .vertical,
                BrowserSidebarDensity.current.rowSeparation(
                    hasBorders: BrowserDeviceAppearanceStore.shared.tabs.borders == .all) / 2
            )
            .browserTabPromotionDestination(
                id: usesMatchedGeometryPromotion ? configuration.promotionID : "",
                in: usesMatchedGeometryPromotion ? configuration.promotionNamespace : nil,
                isActive: usesMatchedGeometryPromotion
            )
            .modifier(
                BrowserPlatformTabPromotionSourceModifier(
                    id: configuration.isPromotionSource ? configuration.promotionID : "",
                    namespace: configuration.isPromotionSource ? configuration.promotionNamespace : nil,
                    usesNativeNavigationTransition:
                        configuration.capabilities.usesNativeNavigationTransition,
                    isEnabled: configuration.isPromotionSource
                )
            )
            .padding(.horizontal, configuration.surfaceHorizontalInset)
            .modifier(
                BrowserSidebarTabRowContainerHitTargets(
                    tabID: configuration.tab.id,
                    browser: configuration.browser,
                    assignment: configuration.assignment,
                    state: sidebarInteraction.sidebarReorderState,
                    joinsReorder: joinsReorder,
                    isSelectionEnabled: configuration.isAvailableForDisplay && !interaction.isRenaming,
                    dismissFromAuxiliaryClick: interaction.dismissFromAuxiliaryClick
                )
            )
            .contentShape(.rect)
            .onHover { interaction.isHovering.wrappedValue = $0 }
            .browserTabDraggable(
                tab: configuration.tab,
                favicons: configuration.favicons,
                profileID: configuration.profileID,
                spaceID: configuration.spaceID,
                dragState: sidebarInteraction.tabDragState,
                reorder: joinsReorder
                    ? BrowserSidebarReorderContext(
                        browser: configuration.browser,
                        spaceAccess: configuration.spaceAccess,
                        state: sidebarInteraction.sidebarReorderState
                    ) : nil,
                parentSplitGroupID: configuration.isSplitGroupMember ? configuration.tab.splitGroupID : nil,
                isEnabled: !interaction.isRenaming
                    && configuration.isAvailableForDisplay
                    && configuration.capabilities.supportsOrganization,
                requiresSelectedSpace: true,
                isTabSelected: configuration.isSelected
            )
            .modifier(
                BrowserSidebarCurrentTabNestTarget(
                    tabID: configuration.tab.id,
                    state: sidebarInteraction.sidebarReorderState,
                    isEnabled: configuration.tab.splitGroupID == nil
                        && !configuration.tab.placement.isDurable
                        && configuration.tab.folderID == nil
                        && configuration.isAvailableForDisplay && joinsReorder
                )
            )
            .crestCollectionItemTransition()
            .accessibilityElement(children: .contain)
            .modifier(
                BrowserTabContextMenu(
                    tab: configuration.tab, context: configuration.context,
                    capabilities: configuration.capabilities,
                    isEnabled: configuration.capabilities.supportsOrganization
                ) { organizationMenu }
            )
    }

    /// Opening the menu ends any drag the same row had started. The lift and
    /// the long press are the same gesture up to the moment one of them wins,
    /// and a menu that opens over a live drag leaves the list mid-reorder.
    private var organizationMenu: some View {
        BrowserTabOrganizationMenu(
            tab: configuration.tab,
            context: configuration.context,
            assignment: configuration.runtimeAssignment,
            isLoaded: configuration.isLoaded,
            renameTab: interaction.beginRenaming,
            changeIcon: interaction.beginChangingIcon
        )
        .tint(.primary)
        .onAppear {
            sidebarInteraction.tabDragState.contextMenuDidOpen(
                for: configuration.runtimeAssignment
            )
            // Both states, because the two lifts are different machines: the
            // pointer drag reports through `tabDragState`, and the touch lift
            // through the reorder state, which has no session left to hear
            // from once this menu has the press.
            sidebarInteraction.sidebarReorderState
                .yieldToCompetingInteraction()
        }
        .onDisappear {
            sidebarInteraction.tabDragState.contextMenuDidClose(
                for: configuration.runtimeAssignment
            )
        }
    }

    private var minHeight: CGFloat {
        configuration.capabilities.tabRowHeight(tabScale: tabScale, dynamicTypeSize: dynamicTypeSize)
    }

    private var usesMatchedGeometryPromotion: Bool {
        configuration.capabilities.usesMatchedGeometryPromotionDestination
    }
}

/// Hover updates the row's appearance without rebuilding its input modifiers.
private struct BrowserSidebarTabRowAppearance: ViewModifier {
    let configuration: BrowserSidebarTabRowConfiguration
    @Binding var isHovering: Bool
    var statusMarks: [BrowserTabStatusMark]? = nil
    @Environment(\.sidebarLayerDepth) private var depth

    func body(content: Content) -> some View {
        content
            .background {
                if statusMarks?.isEmpty != true {
                    BrowserTabStatusSurfaces(
                        tab: BrowserTabStatusSource(
                            tabID: configuration.tab.id, context: configuration.context,
                            canAct: { configuration.isCurrentAndUnlocked }),
                        style: BrowserTabStatusSurfaceStyle(
                            accent: accent, cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth),
                            barOpacity: CrestOpacity.statusSurface),
                        precomputedMarks: statusMarks
                    )
                }
            }
            .modifier(
                BrowserTabAppearanceSurface(
                    appearance: BrowserDeviceAppearanceStore.shared.tabs,
                    accent: accent,
                    isPinned: false,
                    isSelected: configuration.isSelected,
                    isHovering: isHovering
                        || (!configuration.isSplitGroupMember
                            && BrowserSidebarSelection.showsSelected(
                                .tab(configuration.tab.id), in: configuration.context))
                )
            )
            .modifier(BrowserSelectedTabRowAppearance(isSelected: configuration.isSelected))
    }

    private var accent: Color {
        (BrowserDeviceAppearanceStore.shared.tabs.color ?? branding?.primaryColor ?? SpaceBranding.fallbackColor).color
    }

    private var branding: SpaceBranding? {
        configuration.spacePresentation?.branding
            ?? configuration.context.space.settings.look
    }
}

/// A selected row reads as its selected tab style draws it: ink on Crest's
/// white paper on every Space, or on the device's material, the label color
/// in the scheme its material color gives it. Any other row keeps the
/// Space's ink.
///
/// Both states set the same modifiers, so selecting a row changes values
/// rather than the row's structure.
private struct BrowserSelectedTabRowAppearance: ViewModifier {
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.deviceColorScheme) private var deviceColorScheme
    @Environment(\.spaceChromeForeground) private var spaceForeground

    func body(content: Content) -> some View {
        // Only the selected row reads the style, so changing it leaves the rest be.
        let style = isSelected ? BrowserDeviceAppearanceStore.shared.tabs.selectedTabStyle : .standard
        let materialScheme = CrestSurfaceTone.shownScheme(over: colorScheme, window: deviceColorScheme)
        content
            .foregroundStyle(isSelected ? AnyShapeStyle(style.foreground) : AnyShapeStyle(.primary))
            .environment(\.spaceChromeForeground, isSelected ? nil : spaceForeground)
            .environment(\.colorScheme, isSelected ? style.contentScheme(onMaterial: materialScheme) : colorScheme)
    }
}

extension EnvironmentValues {
    /// Whether a tab row takes its place in the sidebar's reorder layout,
    /// measured as the tab's row and dragged as it. A row drawn outside the
    /// sidebar, as a folder's card draws its tabs, joins it only while the
    /// sidebar shows no row of the same tab, which would otherwise share it.
    @Entry var browserSidebarRowJoinsReorder = true
}

private struct BrowserSidebarCurrentTabNestTarget: ViewModifier {
    let tabID: UUID
    let state: BrowserSidebarReorderState
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled, state.isDragging {
            content
                .overlay {
                    BrowserFolderNestDropHighlight(
                        state: state, target: .currentTab(tabID))
                }
        } else {
            content
        }
    }
}

/// Reuses the tab row's already-measured reorder frame for multi-selection and
/// middle-click hit testing inside a sidebar, avoiding duplicate geometry
/// observers and per-row AppKit gesture bridges during scrolling.
private struct BrowserSidebarTabRowContainerHitTargets: ViewModifier {
    let tabID: UUID
    let browser: BrowserStore
    let assignment: BrowserSpaceRuntimeAssignment
    let state: BrowserSidebarReorderState
    let joinsReorder: Bool
    let isSelectionEnabled: Bool
    let dismissFromAuxiliaryClick: @MainActor () -> Void

    @Environment(\.browserSidebarUsesVirtualRowGeometry) private var usesVirtualRowGeometry

    @ViewBuilder
    func body(content: Content) -> some View {
        if joinsReorder, usesVirtualRowGeometry {
            content
                .onChange(of: isSelectionEnabled, initial: true) { _, enabled in
                    if !enabled {
                        state.setRowSelectionDisabled(true, for: .tab(tabID), in: assignment)
                    } else {
                        state.setRowSelectionDisabled(false, for: .tab(tabID), in: assignment)
                    }
                }
                .onChange(of: tabID) { oldTabID, newTabID in
                    guard !isSelectionEnabled else { return }
                    state.setRowSelectionDisabled(false, for: .tab(oldTabID), in: assignment)
                    state.setRowSelectionDisabled(true, for: .tab(newTabID), in: assignment)
                }
                .onDisappear {
                    if !isSelectionEnabled {
                        state.setRowSelectionDisabled(false, for: .tab(tabID), in: assignment)
                    }
                }
        } else if joinsReorder {
            content
                .onAppear {
                    state.setRowAuxiliaryClick(dismissFromAuxiliaryClick, for: .tab(tabID), in: assignment)
                    if !isSelectionEnabled {
                        state.setRowSelectionDisabled(true, for: .tab(tabID), in: assignment)
                    }
                }
                .onChange(of: tabID) { oldTabID, newTabID in
                    state.setRowAuxiliaryClick(nil, for: .tab(oldTabID), in: assignment)
                    state.setRowSelectionDisabled(false, for: .tab(oldTabID), in: assignment)
                    state.setRowAuxiliaryClick(dismissFromAuxiliaryClick, for: .tab(newTabID), in: assignment)
                    state.setRowSelectionDisabled(!isSelectionEnabled, for: .tab(newTabID), in: assignment)
                }
                .onChange(of: assignment) { oldAssignment, newAssignment in
                    state.setRowAuxiliaryClick(nil, for: .tab(tabID), in: oldAssignment)
                    state.setRowSelectionDisabled(false, for: .tab(tabID), in: oldAssignment)
                    state.setRowAuxiliaryClick(dismissFromAuxiliaryClick, for: .tab(tabID), in: newAssignment)
                    state.setRowSelectionDisabled(!isSelectionEnabled, for: .tab(tabID), in: newAssignment)
                }
                .onChange(of: isSelectionEnabled) { _, enabled in
                    state.setRowSelectionDisabled(!enabled, for: .tab(tabID), in: assignment)
                }
                .onDisappear {
                    state.setRowAuxiliaryClick(nil, for: .tab(tabID), in: assignment)
                    state.setRowSelectionDisabled(false, for: .tab(tabID), in: assignment)
                }
        } else {
            content
                .modifier(
                    BrowserTabSelectionTarget(
                        tabID: tabID, browser: browser,
                        assignment: assignment,
                        isEnabled: isSelectionEnabled)
                )
                .modifier(
                    BrowserPlatformRowAuxiliaryClickModifier(
                        perform: dismissFromAuxiliaryClick
                    )
                )
        }
    }
}
