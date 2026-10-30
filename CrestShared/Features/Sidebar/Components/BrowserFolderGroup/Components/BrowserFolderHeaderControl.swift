import SwiftUI

/// Renames in place: Return or focus loss commits, and Escape cancels.
struct BrowserFolderHeaderControl: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    private var folder: FolderStateModel { configuration.folder }
    @Environment(\.browserInteractionCapabilities) private var capabilities
    private var showsTabCounts: Bool { BrowserDeviceAppearanceStore.shared.foldersShowTabCounts }
    private var alwaysVisible: Bool { BrowserDeviceAppearanceStore.shared.foldersAlwaysVisible }
    private var tintsTitle: Bool { BrowserDeviceAppearanceStore.shared.foldersTintTitle }
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
            } else if folder.isTidyHeader {
                BrowserTidyHeaderRow(
                    configuration: configuration, isExpanded: interaction.isExpanded.wrappedValue,
                    toggleExpansion: toggleExpansion)
            } else {
                Button {
                    toggleExpansion()
                } label: {
                    HStack(spacing: 7) {
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

                        Spacer(minLength: 8)
                        if showsTabCounts {
                            BrowserFolderTabCount(folder: folder, space: configuration.context.space).equatable()
                        }
                    }
                    .browserSavedFolderHeaderLayout(configuration: configuration)
                    .contentShape(.rect)
                }
                .buttonStyle(BrowserFolderHeaderButtonStyle())
            }
        }
        .modifier(BrowserSidebarDensityFont(scale: textScale, supportsTouch: capabilities.supportsTouch))
    }

    private func toggleExpansion() {
        guard !sidebarInteraction.sidebarReorderState.suppressesActivation else { return }
        configuration.browser.tabMultiSelection.click(
            .folder(folder.id),
            units: BrowserSidebarSelection.itemUnits(in: configuration.browser))
        interaction.toggleExpansion()
    }
}

/// A header Tidy made: its name in small secondary text, with no icon or
/// count, and a control at its trailing edge that closes the header and its
/// tabs. Pointer shells reveal the control on hover; touch shells always show it.
private struct BrowserTidyHeaderRow: View {
    let configuration: BrowserFolderGroupConfiguration
    let isExpanded: Bool
    let toggleExpansion: () -> Void
    @State private var isHovering = false

    private var folder: FolderStateModel { configuration.folder }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleExpansion) {
                Text(folder.shownTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(folder.shownTitle) header")
            .accessibilityValue(BrowserChromeAccessibility.folderValue(isExpanded: isExpanded))
            .accessibilityHint(isExpanded ? "Collapses this header" : "Expands this header")
            // The close button shows only on hover with a pointer, so the
            // header carries its action for VoiceOver and Full Keyboard Access.
            .accessibilityAction(named: "Close \(folder.shownTitle)", closeHeader)

            Button(action: closeHeader) {
                BrowserSidebarTabTrailingControlLabel(systemName: "xmark", metrics: closeMetrics)
            }
            .modifier(BrowserSidebarTabTrailingControlStyle(metrics: closeMetrics))
            .foregroundStyle(Color.primary)
            .opacity(showsCloseButton ? closeMetrics.closeOpacity(isSelected: false) : 0)
            .disabled(!showsCloseButton)
            .accessibilityLabel("Close \(folder.shownTitle)")
            .accessibilityHint("Closes the tabs under this header")
        }
        .browserSavedFolderHeaderLayout(configuration: configuration)
        .onHover { isHovering = $0 }
    }

    private func closeHeader() {
        _ = configuration.context.tabActions.closeTidyHeader(folder.id)
    }

    /// The close control a tab row draws, so the header's matches it.
    private var closeMetrics: BrowserTabTrailingControlMetrics { configuration.capabilities.trailingControlMetrics }

    private var showsCloseButton: Bool { closeMetrics.isRevealed(isHovering: isHovering, isSelected: false) }
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
