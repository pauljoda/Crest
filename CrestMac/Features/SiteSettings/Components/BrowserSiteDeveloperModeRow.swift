import SwiftUI

/// Whether the site shows the developer toolbar. A site with an origin offers
/// its Developer Mode choice: the default, which the local-pages setting
/// decides, or always on or off. A page without one, such as a file, shows
/// what the default makes of it.
struct BrowserSiteDeveloperModeRow: View {
    let page: BrowserPage
    let origin: SiteOrigin?

    var body: some View {
        if origin != nil {
            Picker(selection: choice) {
                Text(page.isDeveloperModeAutomatic ? "Default (On)" : "Default (Off)")
                    .tag(Bool?.none)
                Text("On").tag(Bool?.some(true))
                Text("Off").tag(Bool?.some(false))
            } label: {
                Label {
                    Text("Developer Mode")
                } icon: {
                    icon
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("site-developer-mode-picker")
        } else {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Developer Mode")
                        .font(.callout.weight(.semibold))
                    Text(page.isDeveloperModeEnabled ? "On" : "Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                icon
            }
        }
    }

    // MARK: - Actions - Presentation

    private var icon: some View {
        Image(systemName: "hammer.fill")
            .foregroundStyle(page.isDeveloperModeEnabled ? .yellow : .secondary)
    }

    private var choice: Binding<Bool?> {
        Binding(
            get: { page.siteDeveloperModeChoice },
            set: { page.chooseSiteDeveloperMode($0) })
    }
}
