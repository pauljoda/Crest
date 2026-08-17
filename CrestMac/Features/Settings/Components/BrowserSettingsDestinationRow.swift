import SwiftUI

struct BrowserSettingsDestinationRow: View {
    let destination: BrowserSettingsDestination
    let isSelected: Bool

    var body: some View {
        CrestSettingsDestinationLabel(
            title: destination.navigationTitle,
            subtitle: destination.subtitle,
            systemImage: destination.symbol,
            color: destination.color,
            compact: true,
            castsShadow: false
        )
        .frame(minHeight: BrowserSettingsVisualPolicy.sidebarRowMinimumHeight)
        .padding(.horizontal, CrestSpacing.extraSmall)
        .contentShape(.rect)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
