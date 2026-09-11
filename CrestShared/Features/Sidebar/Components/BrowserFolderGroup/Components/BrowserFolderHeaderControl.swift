import SwiftUI

/// The folder header's content: the disclosure button a reader opens the
/// folder with, or the field they are renaming it in.
///
/// Renaming happens in place, where the title already is, so the row keeps its
/// icon and its shape and only the text becomes editable. Return commits,
/// Escape abandons the edit, and losing focus commits — the group owns the
/// focus so that last rule has one place to live.
struct BrowserFolderHeaderControl: View {
    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    private var folder: BrowserFolder { configuration.folder }
    @AppStorage(BrowserFolderAppearancePreference.showsTabCountsKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsTabCounts = true
    @AppStorage(BrowserFolderAppearancePreference.alwaysVisibleKey, store: BrowserFolderAppearancePreference.defaults)
    private var alwaysVisible = false
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults) private
        var textScale = 1.0
    @ScaledMetric(relativeTo: .body) private var baseTextSize = BrowserSidebarDensityPolicy.bodySize

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
                    guard !configuration.browser.sidebarReorderState.suppressesActivation else { return }
                    configuration.browser.tabMultiSelection.click(
                        .folder(folder.id), units: BrowserSidebarSelection.itemUnits(in: configuration.browser))
                    interaction.toggleExpansion()
                } label: {
                    HStack(spacing: 7) {
                        BrowserFolderIcon(
                            folder: folder,
                            isExpanded: interaction.isExpanded.wrappedValue,
                            metrics: configuration.headerMetrics
                        )

                        Text(folder.title.isEmpty ? String(localized: "Folder") : folder.title)
                            .foregroundStyle(.primary)
                            .fontWeight(containsCurrentTab ? .semibold : .regular)
                            .lineLimit(1)
                            .modifier(BrowserFolderTitlePressFeedback())

                        Spacer(minLength: 8)
                        if showsTabCounts {
                            Text(configuration.subtreeTabIDs.count, format: .number)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .modifier(BrowserFolderTitlePressFeedback())
                        }
                    }
                    .browserSavedFolderHeaderLayout(configuration: configuration)
                    .contentShape(.rect)
                }
                .buttonStyle(BrowserFolderHeaderButtonStyle())
            }
        }
        .font(textScale == 1 ? nil : .system(size: baseTextSize * BrowserSidebarDensityPolicy.scale(textScale)))
    }

    private var containsCurrentTab: Bool {
        guard alwaysVisible, let selected = configuration.selectedTabID else { return false }
        return configuration.subtreeTabIDs.contains(selected)
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
