import SwiftUI

/// The container a shared settings pane puts its sections in.
///
/// The two shells place a pane's identity differently, and neither placement is
/// negotiable: iOS carries the header *inside* the scroll view as the form's first,
/// chrome-less row and keeps the platform's grouped background; macOS centres the
/// header above a form that the surrounding settings page has already sized and
/// scrolled. Wrapping that difference here is what lets a shared pane's body be
/// its sections and nothing else.
struct BrowserSettingsPane<Content: View>: View {
    let destination: BrowserSettingsDestination
    @ViewBuilder let content: Content

    init(
        _ destination: BrowserSettingsDestination,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        BrowserPlatformSettingsPaneContainer(destination: destination) {
            content
        }
    }
}

#Preview("Settings Pane") {
    BrowserSettingsPane(.general) {
        Section("Example") {
            Text("Setting")
        }
    }
}
