import SwiftUI

/// The native macOS grouped form for a shared settings pane: one centred
/// column of rows, scrolled from the page's own edge.
struct BrowserPlatformSettingsPaneContainer<Content: View>: View {
    @Environment(\.browserSettingsTabState) private var tabState
    @Environment(\.browserSettingsScrollKey) private var scrollKey
    @Environment(\.browserSettingsColumnWidth) private var columnWidth
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
        GeometryReader { geometry in
            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(
                .horizontal,
                BrowserSettingsVisualPolicy.formInset(
                    for: geometry.size.width, columnWidth: columnWidth ?? BrowserSettingsVisualPolicy.formColumnWidth),
                for: .scrollContent
            )
            .browserNativeScrollState(tabState?.scroll(forKey: scrollKey ?? destination.name) ?? standaloneScroll)
        }
        .accessibilityIdentifier("settings-form-\(destination.name)")
    }
}
