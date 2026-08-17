import SwiftUI

struct SidebarTabRowContent: View {
    let configuration: SidebarTabRowConfiguration
    let interaction: SidebarTabRowInteractionContext

    var body: some View {
        HStack(spacing: 0) {
            SidebarTabActivationContent(
                configuration: configuration,
                isRenaming: interaction.isRenaming,
                draftTitle: interaction.draftTitle,
                isTitleFocused: interaction.isTitleFocused,
                commitTitle: interaction.commitTitle,
                cancelTitleEditing: interaction.cancelTitleEditing
            )
            SidebarTabTrailingControl(
                configuration: configuration,
                isHovering: interaction.isHovering.wrappedValue
            )
            .padding(.trailing, 9)
        }
    }
}

private struct SidebarTabActivationContent: View {
    let configuration: SidebarTabRowConfiguration
    let isRenaming: Bool
    @Binding var draftTitle: String
    var isTitleFocused: FocusState<Bool>.Binding
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void

    @ViewBuilder
    var body: some View {
        if isRenaming {
            SidebarTabRenameField(
                configuration: configuration,
                draftTitle: $draftTitle,
                isTitleFocused: isTitleFocused,
                commitTitle: commitTitle,
                cancelTitleEditing: cancelTitleEditing
            )
        } else {
            SidebarTabActivationButton(configuration: configuration)
        }
    }
}

private struct SidebarTabActivationButton: View {
    let configuration: SidebarTabRowConfiguration

    var body: some View {
        Button {
            guard configuration.isCurrentAndUnlocked else { return }
            // A click that ends a reorder must not also open the tab that was
            // just moved; the lift and this button recognise simultaneously.
            guard
                !configuration.browser.sidebarReorderState.suppressesActivation
            else { return }
            BrowserTabActivationPolicy.activate(
                configuration.tab.id,
                selectTab: configuration.browser.selectTab,
                presentPage: configuration.presentSelectedPage
            )
        } label: {
            SidebarTabActivationLabel(configuration: configuration)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .accessibilityLabel(configuration.tab.displayTitle)
        .accessibilityValue(
            BrowserChromeAccessibility.tabValue(isLoaded: configuration.isLoaded)
        )
        .accessibilityAddTraits(configuration.isSelected ? .isSelected : [])
        .accessibilityIdentifier(BrowserTabAccessibilityID.row(configuration.tab.id))
    }
}

private struct SidebarTabActivationLabel: View {
    let configuration: SidebarTabRowConfiguration

    var body: some View {
        Label {
            Text(configuration.tab.displayTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
        } icon: {
            SidebarTabFaviconContent(configuration: configuration)
        }
        .saturation(
            BrowserVisualAccessibilityPolicy.tabResidencySaturation(
                isLoaded: configuration.isLoaded
            )
        )
        .opacity(
            BrowserVisualAccessibilityPolicy.tabResidencyOpacity(
                isLoaded: configuration.isLoaded
            )
        )
        .padding(.leading, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

private struct SidebarTabFaviconContent: View {
    let configuration: SidebarTabRowConfiguration

    var body: some View {
        HStack(spacing: 3) {
            TabFaviconView(
                tab: configuration.tab,
                profileID: configuration.profileID
            )
            .foregroundStyle(configuration.isSelected ? .primary : .secondary)

            if configuration.tab.placement == .saved,
                configuration.tab.isAwayFromSavedLocation,
                let restoreSavedLocation = configuration.restoreSavedLocation
            {
                BrowserTabSavedLocationIndicator(restore: restoreSavedLocation)
            }
        }
    }
}

private struct SidebarTabRenameField: View {
    let configuration: SidebarTabRowConfiguration
    @Binding var draftTitle: String
    var isTitleFocused: FocusState<Bool>.Binding
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void

    var body: some View {
        Label {
            TextField("Tab Name", text: $draftTitle)
                .textFieldStyle(.plain)
                .focused(isTitleFocused)
                .onSubmit(commitTitle)
                .onExitCommand(perform: cancelTitleEditing)
                .accessibilityIdentifier("tab-rename-field")
        } icon: {
            TabFaviconView(
                tab: configuration.tab,
                profileID: configuration.profileID
            )
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

enum BrowserTabActivationPolicy {
    static func activate(
        _ tabID: TabID,
        selectTab: (TabID) -> Void,
        presentPage: () -> Void
    ) {
        selectTab(tabID)
        presentPage()
    }
}
