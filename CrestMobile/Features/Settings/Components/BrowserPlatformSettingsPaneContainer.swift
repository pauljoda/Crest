import SwiftUI

/// The native mobile form container for a shared settings pane.
struct BrowserPlatformSettingsPaneContainer<Content: View>: View {
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
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
        if usesLiveSidebar {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(destination.title).font(.title2.weight(.semibold))
                    BrowserSettingsSectionGrid(allowsColumns: ![.passwords, .about, .extensions].contains(destination))
                    {
                        content
                    }
                }.padding(24)
            }
            .background(BrowserSettingsCanvas.background)
            .accessibilityIdentifier("settings-form-\(destination.rawValue)")
        } else {
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
}
