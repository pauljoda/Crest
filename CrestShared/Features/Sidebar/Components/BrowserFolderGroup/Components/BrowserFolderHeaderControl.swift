import SwiftUI

/// Renames in place: Return or focus loss commits, and Escape cancels. A
/// group's header shows its name alone, in small secondary text. Either kind
/// keeps a `…` button at its trailing edge that opens the folder's menu and,
/// while the folder holds something to close, a button beside it that
/// closes it all: a − on a saved folder and an archive box on a group or an
/// open folder. Both show on hover where a pointer can reveal them, and
/// always on a touch shell.
struct BrowserFolderHeaderControl: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    private var folder: FolderStateModel { configuration.folder }
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    /// The rename field's selection, which takes the whole name as renaming
    /// begins, so typing replaces it on every platform.
    @State private var nameSelection: TextSelection?
    private var appearance: BrowserDeviceAppearanceStore { BrowserDeviceAppearanceStore.shared }
    private var showsTabCounts: Bool { appearance[keyPath: folder.kind.showsTabCounts] }
    private var alwaysVisible: Bool { appearance[keyPath: folder.kind.showsHighlights] }
    private var tintsTitle: Bool { appearance[keyPath: folder.kind.tintsTitle] }
    private var textScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    private var isEditing: Bool {
        interaction.editingFolderRequest.wrappedValue
            == configuration.folderRuntimeAssignment
    }

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: BrowserFolderLayout.headerSpacing) {
                    if folder.kind.showsArtwork {
                        Label {
                            nameField
                        } icon: {
                            folderIcon
                        }
                    } else {
                        nameField
                    }

                    Spacer(minLength: CrestSpacing.small)
                }
                .browserSavedFolderHeaderLayout(configuration: configuration)
            } else {
                Button {
                    guard !sidebarInteraction.sidebarReorderState.suppressesActivation else { return }
                    // The folder reads the selection, so a click that moves it
                    // redraws the folder. Moved with the folder's own motion,
                    // that redraw carries the opening too, rather than drawing
                    // it at once with nothing animated.
                    withAnimation(CrestMotion.disclosure.unlessReducingMotion(reduceMotion)) {
                        configuration.browser.tabMultiSelection.click(
                            .folder(folder.id),
                            units: BrowserSidebarSelection.itemUnits(in: configuration.browser))
                    }
                    interaction.toggleExpansion()
                } label: {
                    HStack(spacing: BrowserFolderLayout.headerSpacing) {
                        if folder.kind.showsArtwork {
                            // A tab row's own label, so the title keeps the
                            // favicons' gap from the icon and starts where
                            // the tabs' titles do.
                            Label {
                                BrowserFolderHeaderTitle(
                                    folder: folder, context: configuration.context, tintsTitle: tintsTitle,
                                    emphasizesShownTab: alwaysVisible
                                )
                                .equatable()
                            } icon: {
                                folderIcon
                            }
                        } else {
                            BrowserGroupHeaderTitle(folder: folder, tintsTitle: tintsTitle)
                        }

                        Spacer(minLength: CrestSpacing.small)
                        if showsTabCounts {
                            BrowserFolderTabCount(folder: folder, space: configuration.context.space).equatable()
                                // Where the `…` button waits for hover, the count
                                // holds its place and gives way to it.
                                .frame(width: countSharesMenuSlot ? menuMetrics.controlSize.width : nil)
                                .opacity(countSharesMenuSlot && isMenuRevealed ? 0 : 1)
                        }
                        if menuMetrics.isAlwaysVisible, trailingControlCount > 0 {
                            // Room for the controls a touch shell always draws
                            // over the header, so the count sits beside them.
                            Color.clear.frame(width: trailingControlsWidth, height: 1)
                        }
                    }
                    .modifier(
                        BrowserFolderHeaderMenuClearance(
                            width: trailingControlsWidth, isActive: titleMeetsTrailingControls)
                    )
                    .browserSavedFolderHeaderLayout(configuration: configuration)
                    // A finger gets the folder's padding too, so a header
                    // shorter than a tab row still takes a whole row's touch.
                    .contentShape(
                        Rectangle().inset(by: capabilities.supportsTouch ? -BrowserFolderLayout.headerTouchReach : 0))
                }
                .buttonStyle(.crestDisclosure)
                // On the disclosure alone, so the `…` button beside it keeps
                // its own label.
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(
                    BrowserChromeAccessibility.folderValue(isExpanded: interaction.isExpanded.wrappedValue)
                )
                .accessibilityHint(accessibilityHint)
                .overlay(alignment: .trailing) {
                    HStack(spacing: 0) {
                        if showsCloseAll {
                            BrowserFolderCloseAllButton(
                                configuration: configuration, interaction: interaction, metrics: menuMetrics,
                                isRevealed: isMenuRevealed
                            )
                        }
                        if showsMenuButton {
                            BrowserFolderMenuButton(
                                configuration: configuration, interaction: interaction, metrics: menuMetrics,
                                isRevealed: isMenuRevealed
                            )
                        }
                    }
                    .padding(.trailing, configuration.headerTrailingInset)
                }
                .onHover { isHovering = $0 }
                // A folder being renamed shows no card.
                .browserTabPreviewSource(.folder(folder), in: configuration.context)
            }
        }
        .modifier(BrowserSidebarDensityFont(scale: textScale, supportsTouch: capabilities.supportsTouch))
    }

    /// The folder's symbol in the tab rows' favicon column.
    private var folderIcon: some View {
        BrowserFolderIcon(
            folder: folder,
            isExpanded: interaction.isExpanded.wrappedValue,
            metrics: configuration.headerMetrics
        )
    }

    /// The field the folder is renamed in.
    private var nameField: some View {
        TextField(folder.kind.namePrompt, text: interaction.draftTitle, selection: $nameSelection)
            .textFieldStyle(.plain)
            .modifier(BrowserFolderNameFieldFont(kind: folder.kind))
            .focused(interaction.isTitleFocused)
            .onChange(of: interaction.isTitleFocused.wrappedValue) { _, focused in
                if focused { selectWholeName() }
            }
            .submitLabel(.done)
            .onSubmit(interaction.commitTitle)
            .onKeyPress(.escape) {
                interaction.cancelTitleEditing()
                return .handled
            }
    }

    /// Selects the whole name once the field has it, which it takes as focus
    /// arrives.
    private func selectWholeName() {
        Task { @MainActor in
            await Task.yield()
            let name = interaction.draftTitle.wrappedValue
            guard !name.isEmpty else { return }
            nameSelection = TextSelection(range: name.startIndex..<name.endIndex)
        }
    }

    private var accessibilityLabel: LocalizedStringKey { folder.kind.spokenName(folder.shownTitle) }

    private var accessibilityHint: LocalizedStringKey {
        folder.kind.disclosureHint(isExpanded: interaction.isExpanded.wrappedValue)
    }

    /// Whether the header offers its menu as a button: wherever the shell
    /// organizes folders, as the context menu does.
    private var showsMenuButton: Bool { capabilities.supportsOrganization }

    /// The size and reveal rule a tab row's trailing control follows, so the
    /// header's matches it.
    private var menuMetrics: BrowserTabTrailingControlMetrics { capabilities.trailingControlMetrics }

    /// Whether the `…` button shows now.
    private var isMenuRevealed: Bool { menuMetrics.isRevealed(isHovering: isHovering, isSelected: false) }

    /// Whether the tab count stands where the `…` button appears on hover,
    /// rather than beside a button that is always there.
    private var countSharesMenuSlot: Bool { showsMenuButton && !menuMetrics.isAlwaysVisible }

    /// Whether the header offers its close-all button now, which closes what
    /// the folder holds to close. Reading it observes the folder's pages.
    private var showsCloseAll: Bool {
        _ = configuration.residencyRevision
        return configuration.hasTabsToClose
    }

    /// How many controls stand at the header's trailing edge.
    private var trailingControlCount: Int { (showsMenuButton ? 1 : 0) + (showsCloseAll ? 1 : 0) }

    /// The width the trailing controls take together.
    private var trailingControlsWidth: CGFloat { menuMetrics.controlSize.width * CGFloat(trailingControlCount) }

    /// Whether the trailing controls show now over the end of the title. A
    /// tab count holds the `…` button's place, and controls that are always
    /// there have their own, but hover-revealed controls reach past a count
    /// when the close-all button stands beside the `…` button, and a button
    /// with no count beside it stands over a long enough name.
    private var titleMeetsTrailingControls: Bool {
        guard !menuMetrics.isAlwaysVisible, isMenuRevealed else { return false }
        return showsCloseAll || (showsMenuButton && !showsTabCounts)
    }
}

/// The button at a folder or group header's trailing edge that closes what
/// the folder holds to close and then closes the folder: a − on a saved
/// folder, whose tabs unload as a tab row's own − unloads its tab, and an
/// archive box on a group or an open folder, whose tabs go to the archive.
private struct BrowserFolderCloseAllButton: View {
    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext
    let metrics: BrowserTabTrailingControlMetrics
    let isRevealed: Bool

    var body: some View {
        Button(action: interaction.closeAllTabs) {
            BrowserSidebarTabTrailingControlLabel(systemName: systemName, metrics: metrics)
        }
        .modifier(BrowserSidebarTabTrailingControlStyle(metrics: metrics))
        .contentShape(.rect)
        .opacity(isRevealed ? 1 : 0)
        .allowsHitTesting(isRevealed)
        .disabled(!configuration.isAvailableForDisplay)
        .accessibilityLabel(accessibilityLabel)
        .help(title)
    }

    /// Unload for a saved folder, whose tabs stay saved, and archive for a
    /// group's or an open folder's.
    private var unloads: Bool { configuration.folder.location.isDurable }

    private var systemName: String { unloads ? "minus" : "archivebox" }

    private var title: LocalizedStringKey { unloads ? "Unload All Tabs" : "Archive All Tabs" }

    private var accessibilityLabel: Text {
        let name = configuration.folder.shownTitle
        return unloads ? Text("Unload All Tabs in \(name)") : Text("Archive All Tabs in \(name)")
    }
}

/// Fades a folder header's title out under its `…` button while the button
/// shows, so a name that reaches the button never runs under it. Only the
/// trailing edge fades: a symbol wider than the icon column reaches past the
/// header's leading edge, and stays whole there.
private struct BrowserFolderHeaderMenuClearance: ViewModifier {
    /// How far the title fades before it reaches the button.
    private static let fadeWidth: CGFloat = 12
    /// How far past the header's edges the mask reaches, so it clips nothing
    /// that overhangs them.
    private static let overflow: CGFloat = 12

    /// The button's width at the header's trailing edge.
    let width: CGFloat
    let isActive: Bool

    func body(content: Content) -> some View {
        content.mask {
            Group {
                if isActive {
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.fadeWidth)
                            .flipsForRightToLeftLayoutDirection(true)
                        Color.clear.frame(width: width)
                    }
                    // Back to the header's own trailing edge, where the
                    // button stands.
                    .padding(.trailing, Self.overflow)
                } else {
                    Rectangle()
                }
            }
            .padding(-Self.overflow)
        }
    }
}

/// The `…` button at a folder or group header's trailing edge, which opens
/// the same menu its context menu does.
private struct BrowserFolderMenuButton: View {
    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext
    let metrics: BrowserTabTrailingControlMetrics
    let isRevealed: Bool

    var body: some View {
        Menu {
            BrowserFolderOrganizationMenu(configuration: configuration, interaction: interaction)
        } label: {
            BrowserSidebarTabTrailingControlLabel(systemName: "ellipsis", metrics: metrics)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .modifier(BrowserSidebarTabTrailingControlStyle(metrics: metrics))
        .tint(.primary)
        .foregroundStyle(.secondary)
        .opacity(isRevealed ? 1 : 0)
        .allowsHitTesting(isRevealed)
        .disabled(!configuration.isAvailableForDisplay)
        .accessibilityLabel(title)
        .help(title)
    }

    private var title: LocalizedStringKey { configuration.folder.kind.actionsTitle }
}

/// The folder's title, in its color where the person asked for it, and bold
/// while the folder holds the shown tab where every folder stays visible. It
/// reads the folder's tabs only for that emphasis, so the rest of the header
/// redraws for neither.
private struct BrowserFolderHeaderTitle: View, @MainActor Equatable {
    let folder: FolderStateModel
    let context: BrowserSidebarListContext
    let tintsTitle: Bool
    let emphasizesShownTab: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(folder.shownTitle)
            .foregroundStyle(
                tintsTitle
                    ? folder.displayColor.folderTitleColor(onDarkBackground: colorScheme == .dark).color
                    : .primary
            )
            .fontWeight(tintsTitle || holdsShownTab ? .semibold : .regular)
            .lineLimit(1)
    }

    private var holdsShownTab: Bool {
        guard emphasizesShownTab else { return false }
        return context.space.tabIDs(inFolder: folder.id).contains { context.window.shownTabIDs.contains($0) }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.folder === rhs.folder && lhs.context == rhs.context && lhs.tintsTitle == rhs.tintsTitle
            && lhs.emphasizesShownTab == rhs.emphasizesShownTab
    }
}

/// How many tabs the folder holds, however deep. It reads the folder's lists,
/// so a tab arriving or leaving redraws this count and not the header.
private struct BrowserFolderTabCount: View, Equatable {
    let folder: FolderStateModel
    let space: SpaceModel

    var body: some View {
        Text(space.tabIDs(inFolder: folder.id).count, format: .number)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.folder === rhs.folder && lhs.space === rhs.space
    }
}

/// A group's name keeps its own size while it is renamed; a folder's takes the
/// sidebar's.
private struct BrowserFolderNameFieldFont: ViewModifier {
    let kind: BrowserFolderKind

    func body(content: Content) -> some View {
        if kind.showsArtwork {
            content
        } else {
            content.modifier(BrowserGroupNameFont())
        }
    }
}
