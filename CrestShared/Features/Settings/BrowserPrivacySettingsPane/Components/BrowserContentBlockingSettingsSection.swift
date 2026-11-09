import SwiftUI

struct BrowserContentBlockingSettingsSection: View {
    @Binding var policy: ContentBlockingPolicy
    let errorDescription: String?
    /// The sites where the Space turned blocking off, from their pages.
    let sitesWithoutBlocking: [SiteOrigin]
    let blockAgain: (SiteOrigin) -> Void

    var body: some View {
        Section("Content blocking") {
            Toggle("Block ads and trackers", isOn: isEnabled)
                .accessibilityIdentifier("content-blocking-enabled")

            if policy.blocksContent, let errorDescription {
                Label(
                    errorDescription,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(CrestColor.warning)
            }

            if policy.blocksContent {
                CrestFormRows(sitesWithoutBlocking, id: \.self) { site in
                    siteRow(site)
                }
            }
        }
    }

    private func siteRow(_ site: SiteOrigin) -> some View {
        HStack(spacing: CrestFormRowMetrics.contentSpacing) {
            VStack(alignment: .leading, spacing: CrestFormRowMetrics.titleSpacing) {
                Text(site.displayName)
                    .lineLimit(1)
                Text("Blocking off")
                    .font(CrestTypography.metadata)
                    .foregroundStyle(CrestColor.textSecondary)
            }

            Spacer(minLength: CrestSpacing.small)

            Button("Turn On Blocking", systemImage: "shield") {
                blockAgain(site)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(CrestChromeButtonStyle())
            .accessibilityLabel("Turn on blocking for \(site.displayName)")
        }
        .frame(minHeight: CrestFormRowMetrics.minimumHeight)
    }

    private var isEnabled: Binding<Bool> {
        Binding {
            policy.blocksContent
        } set: { isEnabled in
            policy = .blocking(isEnabled)
        }
    }
}
