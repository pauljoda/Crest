import SwiftUI

struct BrowserAboutSettingsPane: View {
    static let startsWhatsNewExpanded = false

    let buildInformation: BrowserAboutBuildInformation
    let releaseNotes: [BrowserAboutReleaseNote]

    @State private var showsWhatsNew: Bool

    init(
        buildInformation: BrowserAboutBuildInformation = .current,
        releaseNotes: [BrowserAboutReleaseNote] =
            BrowserAboutReleaseNotes.bundled.currentHighlights()
    ) {
        self.buildInformation = buildInformation
        self.releaseNotes = releaseNotes
        _showsWhatsNew = State(initialValue: Self.startsWhatsNewExpanded)
    }

    var body: some View {
        BrowserSettingsPane(.about) {
            Section {
                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    Text(ProductIdentity.name)
                        .font(.title2.weight(.semibold))
                    Text("An open source browser for Mac, iPhone, and iPad.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                CrestSettingsStatusRow("Version") {
                    Text(buildInformation.version)
                        .textSelection(.enabled)
                }
                CrestSettingsStatusRow("Build") {
                    Text(buildInformation.build)
                        .textSelection(.enabled)
                }
                CrestSettingsStatusRow("Bundle identifier") {
                    Text(buildInformation.bundleIdentifier)
                        .textSelection(.enabled)
                }
            }

            if !releaseNotes.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsWhatsNew) {
                        VStack(
                            alignment: .leading,
                            spacing: CrestSpacing.medium
                        ) {
                            ForEach(releaseNotes) { releaseNote in
                                BrowserAboutReleaseNoteRow(
                                    releaseNote: releaseNote
                                )
                            }
                        }
                        .padding(.vertical, CrestSpacing.small)
                    } label: {
                        Text("What's New in Crest \(buildInformation.version)")
                            .font(.body.weight(.medium))
                    }
                    .disclosureGroupStyle(
                        BrowserAboutWhatsNewDisclosureStyle()
                    )
                }
            }

            Section("Community & support") {
                BrowserAboutLink(
                    title: "Share Feedback on r/CrestBrowser",
                    subtitle: "Ask questions, compare experiences, and discuss ideas",
                    imageName: "AboutReddit",
                    destination: BrowserAboutLinks.feedback,
                    identifier: "about-feedback-link"
                )
                BrowserAboutLink(
                    title: "Report an Issue",
                    subtitle: "Send a reproducible bug report through GitHub Issues",
                    imageName: "AboutGitHub",
                    destination: BrowserAboutLinks.issues,
                    identifier: "about-issues-link"
                )
                BrowserAboutLink(
                    title: "View the Crest Roadmap",
                    subtitle: "Follow planned and completed public work on GitHub",
                    imageName: "AboutGitHub",
                    destination: BrowserAboutLinks.roadmap,
                    identifier: "about-roadmap-link"
                )

                CrestFormFootnote(
                    "Reddit is public. Remove passwords, private URLs, browsing history, and other sensitive information before posting. Use GitHub Issues for reports with a Crest version, Apple platform, and repeatable steps."
                )
            }

            BrowserPlatformSoftwareUpdateSettingsSection()
        }
    }
}

private struct BrowserAboutWhatsNewDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: CrestSpacing.small) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(
                            .degrees(configuration.isExpanded ? 90 : 0)
                        )
                        .accessibilityHidden(true)

                    configuration.label

                    Spacer(minLength: CrestSpacing.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("about-whats-new-disclosure")
            .accessibilityValue(
                configuration.isExpanded ? "Expanded" : "Collapsed"
            )
            .accessibilityHint(
                configuration.isExpanded
                    ? "Hides recent changes"
                    : "Shows recent changes"
            )

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

private struct BrowserAboutLink: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let imageName: String
    let destination: URL
    let identifier: String

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: CrestSpacing.medium) {
                Image(imageName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: CrestSpacing.small)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, CrestSpacing.small)
        }
        .buttonStyle(.crestTertiary)
        .accessibilityIdentifier(identifier)
    }
}

private struct BrowserAboutReleaseNoteRow: View {
    let releaseNote: BrowserAboutReleaseNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.small) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(releaseNote.message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch releaseNote.category {
        case .new: "sparkles"
        case .improved: "arrow.up.circle.fill"
        case .fixed: "checkmark.circle.fill"
        case .internal: "wrench.and.screwdriver.fill"
        }
    }

    private var color: Color {
        switch releaseNote.category {
        case .new: CrestBrandPalette.sky
        case .improved: CrestBrandPalette.butter
        case .fixed: CrestBrandPalette.sage
        case .internal: .secondary
        }
    }
}
