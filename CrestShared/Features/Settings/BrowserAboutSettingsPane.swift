import SwiftUI

struct BrowserAboutSettingsPane: View {
    var buildInformation = BrowserAboutBuildInformation.current

    @Environment(\.browserOpenWebsite) private var openWebsite

    var body: some View {
        BrowserSettingsPane(.about) {
            Section {
                appIdentity
            }

            #if os(macOS)
                BrowserSoftwareUpdateSettingsSection()
            #endif

            if let openWebsite {
                Section {
                    // This build's release page on the site lists what changed in it.
                    Button {
                        Task { openWebsite(await BrowserReleasePage.current().url) }
                    } label: {
                        BrowserAboutLinkLabel(
                            title: "What's New in Crest \(buildInformation.version)",
                            icon: Image(systemName: "sparkles")
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("about-whats-new-link")
                }
            }

            Section {
                BrowserAboutLink(
                    title: "Share Feedback on r/CrestBrowser",
                    imageName: "AboutReddit",
                    destination: BrowserAboutLinks.feedback,
                    identifier: "about-feedback-link"
                )
                BrowserAboutLink(
                    title: "Report an Issue",
                    imageName: "AboutGitHub",
                    destination: BrowserAboutLinks.issues,
                    identifier: "about-issues-link"
                )
                BrowserAboutLink(
                    title: "View the Roadmap",
                    imageName: "AboutGitHub",
                    destination: BrowserAboutLinks.roadmap,
                    identifier: "about-roadmap-link"
                )
            } header: {
                Text("Community and support")
            } footer: {
                CrestFormFootnote("Reddit is public. Leave out private details.")
            }
        }
    }

    private var appIdentity: some View {
        HStack(spacing: 14) {
            BrowserPlatformCurrentAppIcon()
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(ProductIdentity.name)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                // Selectable text is an AppKit view: a label with no value recurses when assistive apps read it.
                Text("Version \(buildInformation.version) (\(buildInformation.build))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Version")
                    .accessibilityValue(
                        Text(
                            "\(buildInformation.version), build \(buildInformation.build), bundle identifier: \(buildInformation.bundleIdentifier)"
                        )
                    )
                    .help(buildInformation.bundleIdentifier)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct BrowserAboutLink: View {
    let title: LocalizedStringResource
    let imageName: String
    let destination: URL
    let identifier: String

    var body: some View {
        Link(destination: destination) {
            BrowserAboutLinkLabel(
                title: title,
                icon: Image(imageName).renderingMode(.original).resizable()
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// A row that leads to a page on the web: its icon, its title, and an arrow
/// that says it leaves Settings.
private struct BrowserAboutLinkLabel: View {
    let title: LocalizedStringResource
    let icon: Image

    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            icon
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: CrestSpacing.small)
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
