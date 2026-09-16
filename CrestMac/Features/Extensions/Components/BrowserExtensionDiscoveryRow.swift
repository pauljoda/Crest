import SwiftUI

struct BrowserExtensionDiscoveryRow: View {
    let item: BrowserExtensionDiscoveryItem
    let space: BrowserSpace
    let isInstalling: Bool
    let isDisabled: Bool
    let additionalSpaces: [BrowserSpace]
    let previousSnapshot: BrowserExtensionPermissionSnapshot?
    let install: (BrowserExtensionInstallationPermissionPolicy.Review) -> Void
    @State private var isSelectingSpaces = false
    @State private var accessReview = BrowserExtensionInstallationPermissionPolicy.Review()

    private var candidate: BrowserExtensionDiscoveryCandidate {
        item.candidate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            HStack(alignment: .center, spacing: CrestSpacing.medium) {
                BrowserExtensionIconView(
                    extensionID: candidate.id,
                    spaceID: space.id,
                    payload: candidate.iconPayload,
                    size: BrowserExtensionsMetrics.discoveryIconSize
                )

                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    HStack(spacing: CrestSpacing.small) {
                        Text(candidate.displayName)
                            .font(.body.weight(.semibold))
                        if let version = candidate.version {
                            Text(version)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if let description = candidate.displayDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Label(
                        "\(item.source.title) · \(item.source.detail)",
                        systemImage: item.source.symbol
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }

                Spacer(minLength: CrestSpacing.medium)

                Button(action: { install(accessReview) }) {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Adding \(candidate.displayName)")
                    } else {
                        Text("Add")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled)
            }

            BrowserExtensionInstallConsentText()
            Button("Install in other Spaces…") { isSelectingSpaces = true }
                .disabled(isDisabled)

            DisclosureGroup("Review Access and Compatibility") {
                VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                    sourceReview
                    LabeledContent("Install In", value: "\(space.name) Space")

                    if !candidate.requestedPermissions.isEmpty {
                        BrowserExtensionInstallAccessGroup(
                            title: "Permissions",
                            values: candidate.requestedPermissions,
                            emptyText: "",
                            choices: $accessReview.permissions,
                            defaultAllowance: accessReview.allowsPermission
                        )
                    }
                    if !candidate.requestedHosts.isEmpty {
                        BrowserExtensionInstallAccessGroup(
                            title: "Website Access",
                            values: candidate.requestedHosts,
                            emptyText: "",
                            choices: $accessReview.hosts,
                            defaultAllowance: accessReview.allowsHost
                        )
                    }
                    if !candidate.errors.isEmpty {
                        BrowserSafariWebExtensionAccessList(
                            title: "Compatibility Warnings",
                            values: candidate.errors
                        )
                        .foregroundStyle(.orange)
                    }
                }
                .padding(.top, CrestSpacing.small)
                .padding(.leading, CrestSpacing.medium)
            }
            .font(.callout)
        }
        .sheet(isPresented: $isSelectingSpaces) {
            BrowserExtensionInstallSpacesPage(
                primarySpaceName: space.name, spaces: additionalSpaces,
                selection: $accessReview.additionalSpaceIDs,
                goBack: { isSelectingSpaces = false }
            )
            .padding(CrestSpacing.extraLarge)
            .frame(width: BrowserExtensionInstallMetrics.width)
        }
        .onChange(of: previousSnapshot, initial: true) {
            accessReview.previousSnapshot = previousSnapshot
        }
        .padding(.vertical, CrestSpacing.small)
    }

    @ViewBuilder
    private var sourceReview: some View {
        switch item.candidate {
        case .safariApplication(let applicationCandidate):
            LabeledContent("Type", value: "Safari Web Extension")
            LabeledContent(
                "Signed Developer",
                value: applicationCandidate.source.developerTeamIdentifier
                    ?? "Verified"
            )
        case .safariCustom:
            LabeledContent("Type", value: "Safari Custom WebExtension")
            LabeledContent("Source", value: "Copied from Safari")
            Label {
                Text(
                    "Crest installs its own copy. Safari permissions, profile assignments, and updates are not imported."
                )
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
