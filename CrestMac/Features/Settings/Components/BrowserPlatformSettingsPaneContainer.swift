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
        Form {
            content
        }
        .crestSettingsForm()
        .accessibilityIdentifier("settings-form-\(destination.rawValue)")
    }
}

#Preview("Settings pane container") {
    BrowserPlatformSettingsPaneContainer(destination: .general) {
        Section("Example") {
            Text("Setting")
        }
    }
}
