import SwiftUI

/// What a sidebar tab row draws inside its surface: the tab, and the one
/// control that puts it away.
struct BrowserSidebarTabRowContent: View {
    let configuration: BrowserSidebarTabRowConfiguration
    let interaction: BrowserSidebarTabRowInteractionContext

    var body: some View {
        HStack(spacing: configuration.metrics.contentSpacing) {
            leadingContent
            BrowserSidebarTabTrailingControl(
                configuration: configuration,
                isHovering: interaction.isHovering.wrappedValue
            )
            .padding(.trailing, configuration.metrics.contentTrailingInset)
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if interaction.isRenaming {
            BrowserSidebarTabRenameField(
                tab: configuration.tab,
                profileID: configuration.profileID,
                metrics: configuration.metrics,
                leadingInset: configuration.metrics.contentLeadingInset,
                draftTitle: interaction.draftTitle,
                isTitleFocused: interaction.isTitleFocused,
                commitTitle: interaction.commitTitle,
                cancelTitleEditing: interaction.cancelTitleEditing
            )
        } else {
            BrowserSidebarTabActivationButton(
                tab: configuration.tab,
                profileID: configuration.profileID,
                isSelected: configuration.isSelected,
                isLoaded: configuration.isLoaded,
                metrics: configuration.metrics,
                leadingInset: configuration.metrics.contentLeadingInset,
                restoreSavedLocation: configuration.restoreSavedLocation,
                select: interaction.activate
            )
        }
    }
}
