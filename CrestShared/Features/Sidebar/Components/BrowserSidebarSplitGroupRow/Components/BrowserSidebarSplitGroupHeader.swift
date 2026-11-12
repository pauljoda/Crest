import SwiftUI

/// The group's own row, standing as a folder's header does: the stacked
/// icons in the folder symbol's column, a chevron in their place while the
/// split is collapsed, the title in a folder title's font, and the same
/// height. A click opens or closes the split's tabs under it, and a double
/// click renames it.
///
/// It is also the only part of the split that belongs to the group rather
/// than to one of its tabs, so it carries the group's drag and its menu,
/// which holds "Separate All Tabs", behind the trailing ellipsis too.
struct BrowserSidebarSplitGroupHeader: View {
    let configuration: BrowserSidebarSplitGroupRowConfiguration
    let interaction: BrowserSidebarSplitGroupRowInteractionContext

    @Environment(\.sidebarRowContentIndent) private var folderIndent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    var body: some View {
        HStack(spacing: BrowserFolderLayout.headerSpacing) {
            if interaction.isRenaming {
                HStack(spacing: BrowserFolderLayout.headerSpacing) {
                    icon
                    TextField("Split View Name", text: interaction.draftTitle)
                        .textFieldStyle(.plain)
                        .focused(interaction.isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit(interaction.commitTitle)
                        .onKeyPress(.escape) {
                            interaction.cancelTitleEditing()
                            return .handled
                        }
                        .accessibilityIdentifier("split-group-rename-field")
                    Spacer(minLength: CrestSpacing.small)
                }
            } else {
                Button(action: toggleCollapse) {
                    HStack(spacing: BrowserFolderLayout.headerSpacing) {
                        icon
                        BrowserSidebarSplitGroupTitle(configuration: configuration)
                        Spacer(minLength: CrestSpacing.small)
                    }
                    .frame(maxHeight: .infinity)
                    // A finger gets the split's padding too, as a folder's
                    // header does.
                    .contentShape(
                        Rectangle().inset(
                            by: configuration.capabilities.supportsTouch ? -BrowserFolderLayout.headerTouchReach : 0))
                }
                .buttonStyle(.crestDisclosure)
                #if os(macOS)
                    .simultaneousGesture(TapGesture(count: 2).onEnded(interaction.beginRenaming))
                #endif
                .modifier(
                    BrowserPlatformRowAuxiliaryClickModifier(
                        perform: configuration.canClose ? interaction.closeSplit : nil
                    )
                )
                .accessibilityLabel(configuration.shownTitle)
                .accessibilityValue(BrowserChromeAccessibility.folderValue(isExpanded: !configuration.isCollapsed))
                .accessibilityHint(configuration.isCollapsed ? "Expands this Split View" : "Collapses this Split View")
                .accessibilityAddTraits(configuration.isPresented ? .isSelected : [])
            }
            actionsMenu
        }
        .browserFolderHeaderLayout(metrics: headerMetrics, leadingInset: leadingInset)
        .modifier(
            BrowserSidebarDensityFont(scale: tabScale, supportsTouch: configuration.capabilities.supportsTouch)
        )
        // The separation a tab row keeps, as a folder's header does.
        .padding(
            .vertical,
            BrowserSidebarDensity(tabScale).rowSeparation(
                hasBorders: BrowserDeviceAppearanceStore.shared.tabs.borders == .all) / 2
        )
        .contentShape(.rect)
        .browserSplitGroupDraggable(
            item: configuration.dragItem,
            members: configuration.members,
            favicons: configuration.context.favicons,
            placement: configuration.placement,
            folderID: configuration.folderID,
            reorder: configuration.reorderContext,
            isEnabled: configuration.isAvailableForDisplay && configuration.capabilities.supportsOrganization
                && !interaction.isRenaming,
            requiresSelectedSpace: true
        )
        .contextMenu {
            if configuration.capabilities.supportsOrganization {
                BrowserSidebarSplitGroupContextMenu(configuration: configuration, interaction: interaction)
                    .tint(.primary)
                    .onAppear {
                        configuration.sidebarInteraction.sidebarReorderState.yieldToCompetingInteraction()
                    }
            }
        }
        .onChange(of: interaction.isTitleFocused.wrappedValue) { _, focused in
            if !focused, interaction.isRenaming {
                interaction.commitTitle()
            }
        }
    }

    private var headerMetrics: BrowserFolderHeaderMetrics {
        configuration.capabilities.savedFolderHeaderMetrics
    }

    /// The icons' column: the member favicons' own, past any folders around
    /// the split.
    private var leadingInset: CGFloat {
        configuration.headerLeadingInset + folderIndent
    }

    /// The symbol column: the stacked icons, or a chevron while the split is
    /// collapsed, turning as the Space header's does.
    private var icon: some View {
        CrestDisclosureIcon(isCollapsed: configuration.isCollapsed, glyphSize: chevronSize) {
            BrowserSidebarSplitGroupIcon(configuration: configuration)
        }
        .frame(width: (headerMetrics.iconWidth + 6) * BrowserSidebarDensity(tabScale).scale)
        .browserIconCustomizationPopover(
            BrowserIconCustomizationPresentation(
                isPresented: interaction.isChoosingIcon,
                title: "Split View Icon",
                currentEmoji: configuration.emojiIcon,
                showsReset: configuration.emojiIcon != nil,
                resetTitle: "Use Stacked Icons",
                setEmoji: interaction.setEmojiIcon,
                reset: interaction.resetIcon
            )
        )
    }

    /// A collapsed split's chevron, sized to sit in the column the stacked
    /// icons fill.
    private var chevronSize: CGFloat {
        configuration.metrics.headerGlyphSize * 0.75 * BrowserSidebarDensity(tabScale).scale
    }

    /// The group's actions, the same ones its context menu holds.
    private var actionsMenu: some View {
        Menu {
            BrowserSidebarSplitGroupContextMenu(configuration: configuration, interaction: interaction)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: headerMetrics.iconWidth, height: headerMetrics.iconWidth)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .crestMenuActionLabelStyle()
        .tint(.primary)
        .fixedSize()
        .accessibilityLabel("Split View actions")
        .disabled(!configuration.isAvailableForDisplay)
    }

    /// Opens or closes the split's tabs with a folder's own motion, unless
    /// the click ended a drag.
    private func toggleCollapse() {
        guard !configuration.sidebarInteraction.sidebarReorderState.suppressesActivation else { return }
        withAnimation(CrestMotion.disclosure.unlessReducingMotion(reduceMotion)) {
            interaction.toggleCollapse()
        }
    }
}

/// The split's title as a folder's reads: in the split's color where the
/// person tints folder titles, and bold while the split holds the shown tab
/// where every folder stays visible.
private struct BrowserSidebarSplitGroupTitle: View {
    let configuration: BrowserSidebarSplitGroupRowConfiguration

    @Environment(\.colorScheme) private var colorScheme
    private var tintsTitle: Bool { BrowserDeviceAppearanceStore.shared.foldersTintTitle }
    private var alwaysVisible: Bool { BrowserDeviceAppearanceStore.shared.foldersAlwaysVisible }

    var body: some View {
        Text(configuration.shownTitle)
            .foregroundStyle(
                tintsTitle
                    ? (configuration.tint ?? .folderDefault).folderTitleColor(onDarkBackground: colorScheme == .dark)
                        .color
                    : .primary
            )
            .fontWeight(tintsTitle || (alwaysVisible && configuration.isPresented) ? .semibold : .regular)
            .lineLimit(1)
    }
}

private struct BrowserSidebarSplitGroupIcon: View {
    let configuration: BrowserSidebarSplitGroupRowConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    /// How large each card of the stack draws: a member favicon's size, at
    /// the sidebar's density.
    private var glyphSize: CGFloat {
        configuration.metrics.headerGlyphSize * BrowserSidebarDensity(tabScale).scale
    }

    var body: some View {
        Group {
            if let emoji = configuration.emojiIcon {
                Text(emoji)
                    .font(.system(size: glyphSize))
            } else {
                faviconStack
            }
        }
        .frame(
            width: glyphSize * 1.45,
            height: glyphSize
        )
        .accessibilityHidden(true)
    }

    private var faviconStack: some View {
        ZStack(alignment: .leading) {
            ForEach(
                Array(deckMembers.enumerated()),
                id: \.element.id
            ) { index, member in
                let isFocused = member.id == configuration.focusedMemberID
                let shouldAnimateLift = !reduceMotion

                TabStateFaviconView(
                    tab: member,
                    favicons: configuration.context.favicons,
                    profileID: configuration.profileID,
                    size: glyphSize
                )
                .padding(1)
                .background { CrestSurfaceLayer(shape: Circle()) }
                .overlay {
                    Circle()
                        .strokeBorder(
                            Color.primary.opacity(CrestOpacity.border),
                            lineWidth: CrestLayout.hairline
                        )
                }
                .scaleEffect(deckScale(at: index))
                .rotationEffect(
                    .degrees(deckRotation(at: index)),
                    anchor: .bottom
                )
                .offset(
                    x: deckHorizontalOffset(at: index),
                    y: deckVerticalOffset(at: index)
                )
                .zIndex(Double(index))
                .transition(.scale(scale: 0.82).combined(with: .opacity))
                .animation(deckAnimation, value: configuration.focusedMemberID)
                .keyframeAnimator(
                    initialValue: CGFloat.zero,
                    trigger: configuration.focusedMemberID
                ) { content, lift in
                    content.offset(
                        y: isFocused && shouldAnimateLift ? lift : 0
                    )
                } keyframes: { _ in
                    CubicKeyframe(
                        -glyphSize * 0.18,
                        duration: CrestMotion.collectionTransition / 2
                    )
                    CubicKeyframe(
                        0,
                        duration: CrestMotion.collectionTransition / 2
                    )
                }
            }
        }
    }

    private var deckMembers: [TabStateModel] {
        BrowserSidebarSplitGroupIconDeck.orderedMembers(
            configuration.members,
            focusedMemberID: configuration.focusedMemberID
        )
    }

    private var frontIndex: Int {
        max(deckMembers.count - 1, 0)
    }

    private func deckScale(at index: Int) -> CGFloat {
        1 - CGFloat(frontIndex - index) * 0.055
    }

    private func deckRotation(at index: Int) -> Double {
        Double(index - frontIndex) * 3.5
    }

    private func deckHorizontalOffset(at index: Int) -> CGFloat {
        CGFloat(index) * glyphSize * 0.28
    }

    private func deckVerticalOffset(at index: Int) -> CGFloat {
        CGFloat(frontIndex - index) * glyphSize * 0.045
    }

    private var deckAnimation: Animation? {
        CrestMotion.collection.unlessReducingMotion(reduceMotion)
    }
}

/// A split may contain more members than the compact header can draw. The
/// focused member is always admitted to the visible deck and placed last so it
/// renders above the other cards; stable tab identity then lets SwiftUI move
/// each favicon through the deck instead of replacing the whole stack.
enum BrowserSidebarSplitGroupIconDeck {
    static let visibleLimit = 3

    static func orderedMembers<Member: Identifiable>(
        _ members: [Member],
        focusedMemberID: UUID?,
        limit: Int = visibleLimit
    ) -> [Member] where Member.ID == UUID {
        guard limit > 0 else { return [] }

        var visible = Array(members.prefix(limit))
        guard let focused = members.first(where: { $0.id == focusedMemberID })
        else { return visible }

        if !visible.contains(where: { $0.id == focused.id }) {
            if visible.isEmpty {
                visible.append(focused)
            } else {
                visible[visible.index(before: visible.endIndex)] = focused
            }
        }

        visible.removeAll { $0.id == focused.id }
        visible.append(focused)
        return visible
    }
}
