import SwiftUI

struct SidebarTabFaviconContent: View {
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

#Preview {
    SidebarTabFaviconContent(
        configuration: SidebarTabRowPreviewFixture.configuration(
            placement: .saved
        )
    )
    .padding()
}
