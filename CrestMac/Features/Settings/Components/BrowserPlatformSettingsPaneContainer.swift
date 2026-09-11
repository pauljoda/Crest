import SwiftUI

/// The native macOS form container for a shared settings pane.
struct BrowserPlatformSettingsPaneContainer<Content: View>: View {
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
            BrowserSettingsSectionGrid(allowsColumns: ![.passwords, .about, .extensions].contains(destination)) {
                content
            }
            .padding(24)
        }
        .accessibilityIdentifier("settings-form-\(destination.rawValue)")
    }
}
