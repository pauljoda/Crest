import SwiftUI

/// The native macOS grouped form for a shared settings pane: one centred
/// column of rows.
///
/// On macOS 27 the form spans the whole page, as
/// ``BrowserSettingsPageWideColumn`` describes. On macOS 26 the form is the
/// column itself, placed by ``BrowserSettingsColumnLayout``.
struct BrowserPlatformSettingsPaneContainer<Content: View>: View {
    // MARK: - Variables

    @Environment(\.browserSettingsTabState) private var tabState
    @Environment(\.browserSettingsScrollKey) private var scrollKey
    @Environment(\.browserSettingsColumnWidth) private var columnWidth
    @State private var standaloneScroll = BrowserNativeScrollState()
    let destination: BrowserSettingsDestination
    @ViewBuilder let content: Content

    // MARK: - Initializers

    init(
        destination: BrowserSettingsDestination,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.content = content()
    }

    // MARK: - Actions - Drawing

    var body: some View {
        Group {
            if #available(macOS 27, *) {
                form
                    .modifier(BrowserSettingsPageWideColumn(columnWidth: shownColumnWidth))
            } else {
                BrowserSettingsColumnLayout(columnWidth: shownColumnWidth) {
                    form
                }
            }
        }
        .accessibilityIdentifier("settings-form-\(destination.name)")
    }

    private var form: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .browserNativeScrollState(tabState?.scroll(forKey: scrollKey ?? destination.name) ?? standaloneScroll)
    }

    private var shownColumnWidth: CGFloat {
        columnWidth ?? BrowserSettingsLayout.formColumnWidth
    }
}
