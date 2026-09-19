import SwiftUI

/// The native macOS form container for a shared settings pane.
struct BrowserPlatformSettingsPaneContainer<Content: View>: View {
    @Environment(\.browserSettingsTabState) private var tabState
    @State private var standaloneScroll = BrowserNativeScrollState()
    let destination: BrowserSettingsDestination
    @ViewBuilder let content: Content

    init(
        destination: BrowserSettingsDestination,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        ScrollView {
            BrowserSettingsSectionGrid(allowsColumns: ![.passwords, .about].contains(destination)) {
                content
            }
            .padding(24)
        }
        .browserNativeScrollState(tabState?.scroll(for: destination) ?? standaloneScroll)
        .accessibilityIdentifier("settings-form-\(destination.rawValue)")
    }
}
