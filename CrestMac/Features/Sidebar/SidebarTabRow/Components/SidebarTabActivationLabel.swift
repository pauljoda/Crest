import SwiftUI

struct SidebarTabActivationLabel: View {
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

#Preview {
    SidebarTabActivationLabel(
        configuration: SidebarTabRowPreviewFixture.configuration()
    )
    .frame(width: 280, height: CrestLayout.sidebarRowHeight)
    .padding()
}
