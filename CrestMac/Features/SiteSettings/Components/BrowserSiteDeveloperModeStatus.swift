import SwiftUI

/// Shows whether this page has Developer Mode on and turns it on or off for
/// the page when clicked. Turning it off also clears the viewport preset.
struct BrowserSiteDeveloperModeStatus: View {
    let page: BrowserPage
    @State private var isHovering = false

    var body: some View {
        Button {
            page.setDeveloperToolbarVisible(!page.isDeveloperModeEnabled)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Developer Mode")
                        .font(.callout.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(
                        page.isDeveloperModeEnabled ? .yellow : .secondary
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CrestSpacing.small)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .crestInteractiveSurface(isSelected: false, isHovering: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Developer Mode")
        .accessibilityValue(detail)
        .accessibilityIdentifier("site-developer-mode-toggle")
    }

    private var detail: String {
        guard page.isDeveloperModeEnabled else { return "Off" }
        guard page.isDeveloperModeEnabledAutomatically else { return "On" }
        return BrowserAppPreferenceStore.shared.developerToolbar == .allWebsites
            ? "On automatically" : "On automatically for localhost"
    }
}
