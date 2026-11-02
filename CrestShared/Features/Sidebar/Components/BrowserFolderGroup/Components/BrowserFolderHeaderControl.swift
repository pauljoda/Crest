import SwiftUI

/// Renames in place: Return or focus loss commits, and Escape cancels. A
/// group's header shows its name alone, in small secondary text. Either kind
/// keeps a `…` button at its trailing edge that opens the folder's menu: on
/// hover where a pointer can reveal it, and always on a touch shell.
struct BrowserFolderHeaderControl: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    private var folder: FolderStateModel { configuration.folder }
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    private var appearance: BrowserDeviceAppearanceStore { BrowserDeviceAppearanceStore.shared }
    private var showsTabCounts: Bool {
        folder.isGroup ? appearance.groupsShowTabCounts : appearance.foldersShowTabCounts
    }
    private var alwaysVisible: Bool {
        folder.isGroup ? appearance.groupsAlwaysVisible : appearance.foldersAlwaysVisible
    }
    private var tintsTitle: Bool { folder.isGroup ? appearance.groupsTintTitle : appearance.foldersTintTitle }
    private var textScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    private var isEditing: Bool {
        interaction.editingFolderRequest.wrappedValue
            == configuration.folderRuntimeAssignment
    }

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 7) {
                    BrowserFolderIcon(
                        folder: folder,
                        isExpanded: interaction.isExpanded.wrappedValue,
                        metrics: configuration.headerMetrics
                    )

                    TextField("Folder Name", text: interaction.draftTitle)
                        .textFieldStyle(.plain)
                        .focused(interaction.isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit(interaction.commitTitle)
                        .onKeyPress(.escape) {
                            interaction.cancelTitleEditing()
                            return .handled
                        }

                    Spacer(minLength: 8)
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
                    HStack(spacing: 7) {
                        if folder.isGroup {
                            BrowserGroupHeaderTitle(folder: folder, tintsTitle: tintsTitle)
                        } else {
                            BrowserFolderIcon(
                                folder: folder,
                                isExpanded: interaction.isExpanded.wrappedValue,
                                metrics: configuration.headerMetrics
                            )

                            BrowserFolderHeaderTitle(
                                folder: folder, context: configuration.context, tintsTitle: tintsTitle,
                                emphasizesShownTab: alwaysVisible
                            )
                            .equatable()
                        }

                        Spacer(minLength: 8)
                        if showsTabCounts {
                            BrowserFolderTabCount(folder: folder, space: configuration.context.space).equatable()
                        }
                        if showsMenuButton {
                            // Room for the `…` button drawn over the header, so
                            // the count never sits under it.
                            Color.clear.frame(width: menuMetrics.controlSize.width, height: 1)
                        }
                    }
                    .browserSavedFolderHeaderLayout(configuration: configuration)
                    // A finger gets the folder's padding too, so a header
                    // shorter than a tab row still takes a whole row's touch.
                    .contentShape(
                        Rectangle().inset(by: capabilities.supportsTouch ? -BrowserFolderLayout.headerTouchReach : 0))
                }
                .buttonStyle(BrowserFolderHeaderButtonStyle())
                // On the disclosure alone, so the `…` button beside it keeps
                // its own label.
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(
                    BrowserChromeAccessibility.folderValue(isExpanded: interaction.isExpanded.wrappedValue)
                )
                .accessibilityHint(accessibilityHint)
                .overlay(alignment: .trailing) {
                    if showsMenuButton {
                        BrowserFolderMenuButton(
                            configuration: configuration, interaction: interaction, metrics: menuMetrics,
                            isRevealed: menuMetrics.isRevealed(isHovering: isHovering, isSelected: false)
                        )
                        .padding(.trailing, configuration.headerMetrics.contentTrailingInset)
                    }
                }
                .onHover { isHovering = $0 }
            }
        }
        .modifier(BrowserSidebarDensityFont(scale: textScale, supportsTouch: capabilities.supportsTouch))
    }

    private var accessibilityLabel: LocalizedStringKey {
        folder.isGroup ? "\(folder.shownTitle) group" : "\(folder.shownTitle) folder"
    }

    private var accessibilityHint: LocalizedStringKey {
        switch (folder.isGroup, interaction.isExpanded.wrappedValue) {
        case (true, true): "Collapses this group"
        case (true, false): "Expands this group"
        case (false, true): "Collapses this folder"
        case (false, false): "Expands this folder"
        }
    }

    /// Whether the header offers its menu as a button: wherever the shell
    /// organizes folders, as the context menu does.
    private var showsMenuButton: Bool { capabilities.supportsOrganization }

    /// The size and reveal rule a tab row's trailing control follows, so the
    /// header's matches it.
    private var menuMetrics: BrowserTabTrailingControlMetrics { capabilities.trailingControlMetrics }
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

    private var title: LocalizedStringKey { configuration.folder.isGroup ? "Group actions" : "Folder actions" }
}

/// A group's name: small, semibold and secondary, or in the group's color
/// where the person asked for it.
private struct BrowserGroupHeaderTitle: View {
    let folder: FolderStateModel
    let tintsTitle: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(folder.shownTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(
                tintsTitle
                    ? folder.displayColor.folderTitleColor(onDarkBackground: colorScheme == .dark).color
                    : .secondary
            )
            .lineLimit(1)
            .modifier(BrowserFolderTitlePressFeedback())
    }
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
            .modifier(BrowserFolderTitlePressFeedback())
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
            .modifier(BrowserFolderTitlePressFeedback())
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.folder === rhs.folder && lhs.space === rhs.space
    }
}

extension EnvironmentValues {
    @Entry fileprivate var folderHeaderIsPressed = false
}

/// PlainButtonStyle fades its entire label. Only the title and count acknowledge
/// a press here, keeping the animated artwork's color steady.
private struct BrowserFolderHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.folderHeaderIsPressed, configuration.isPressed)
    }
}

private struct BrowserFolderTitlePressFeedback: ViewModifier {
    @Environment(\.folderHeaderIsPressed) private var isPressed

    func body(content: Content) -> some View {
        content.opacity(isPressed ? 0.55 : 1)
    }
}
