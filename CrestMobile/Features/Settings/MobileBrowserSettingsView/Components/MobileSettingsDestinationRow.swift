import SwiftUI

struct MobileSettingsDestinationRow: View {
    let destination: BrowserSettingsDestination

    var body: some View {
        CrestSettingsDestinationLabel(
            title: destination.title,
            subtitle: destination.subtitle,
            systemImage: destination.symbol,
            color: destination.color
        )
        .padding(.vertical, CrestSpacing.extraExtraSmall)
        .accessibilityElement(children: .contain)
    }
}
