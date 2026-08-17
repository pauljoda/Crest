import SwiftUI

/// The native mobile form container for a shared settings pane.
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
        Form {
            BrowserSettingsPaneHeader(
                destination: destination,
                identifier: "settings-header-\(destination.rawValue)",
                layout: .mobilePage
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            content
        }
        .accessibilityIdentifier("settings-form-\(destination.rawValue)")
    }
}
