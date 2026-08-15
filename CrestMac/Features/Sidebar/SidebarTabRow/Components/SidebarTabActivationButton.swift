import SwiftUI

struct SidebarTabActivationButton: View {
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

#Preview {
    SidebarTabActivationButton(
        configuration: SidebarTabRowPreviewFixture.configuration()
    )
    .frame(width: 280, height: CrestLayout.sidebarRowHeight)
    .padding()
}
