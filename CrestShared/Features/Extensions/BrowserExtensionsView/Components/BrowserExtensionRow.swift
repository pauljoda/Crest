import SwiftUI

struct BrowserExtensionRow: View {
    let summary: BrowserExtensionSummary
    let spaceID: SpaceID
    let extensionControllerPool: BrowserExtensionControllerPool
    let platformActions: BrowserExtensionPlatformActions
    let isBusy: Bool
    let setEnabled: @MainActor @Sendable (Bool) -> Void
    let setPermissionDecision:
        @MainActor @Sendable (
            String,
            BrowserExtensionAccessDecision
        ) -> Void
    let setHostDecision:
        @MainActor @Sendable (
            String,
            BrowserExtensionAccessDecision
        ) -> Void
    let requestRemoval: @MainActor @Sendable () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                if !summary.requestedPermissions.isEmpty {
                    BrowserExtensionAccessSection(
                        title: "Permissions",
                        values: summary.requestedPermissions,
                        decision: {
                            extensionControllerPool.permissionDecision(
                                for: $0,
                                extensionID: summary.id,
                                in: spaceID
                            )
                        },
                        setDecision: {
                            setPermissionDecision($0, $1)
                        }
                    )
                }

                if !summary.requestedHosts.isEmpty {
                    BrowserExtensionAccessSection(
                        title: "Website Access",
                        values: summary.requestedHosts,
                        decision: {
                            extensionControllerPool.hostDecision(
                                for: $0,
                                extensionID: summary.id,
                                in: spaceID
                            )
                        },
                        setDecision: {
                            setHostDecision($0, $1)
                        }
                    )
                }

                if !summary.unsupportedAPIs.isEmpty {
                    BrowserExtensionValueList(
                        title: "Unsupported APIs",
                        values: summary.unsupportedAPIs,
                        symbol: "exclamationmark.circle"
                    )
                }

                if let issue = BrowserExtensionSummaryPresentation.issue(
                    for: summary
                ) {
                    BrowserExtensionIssueSection(issue: issue)
                }

                if summary.hasOptionsPage,
                    summary.isLoaded,
                    platformActions.supportsOptionsPage
                {
                    Button(
                        "Extension Settings",
                        systemImage: "gearshape"
                    ) {
                        platformActions.openOptionsPage(
                            extensionID: summary.id,
                            in: spaceID
                        )
                    }
                }

                Button(
                    "Remove Extension",
                    systemImage: "trash",
                    role: .destructive,
                    action: requestRemoval
                )
            }
            .padding(.top, CrestSpacing.medium)
            .padding(.leading, BrowserExtensionsMetrics.expandedContentIndent)
        } label: {
            HStack(alignment: .center, spacing: CrestSpacing.medium) {
                BrowserExtensionIconView(
                    extensionID: summary.id,
                    spaceID: spaceID,
                    payload: summary.iconPayload
                )
                .overlay(alignment: .bottomTrailing) {
                    if BrowserExtensionSummaryPresentation.issue(
                        for: summary
                    ) != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .orange)
                            .font(.caption)
                    }
                }

                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    HStack(spacing: CrestSpacing.small) {
                        Text(summary.displayName)
                            .font(.body.weight(.medium))
                        if let version = summary.version {
                            Text(version)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(BrowserExtensionSummaryPresentation.detailText(for: summary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let sourceDisplayName = summary.sourceDisplayName {
                        Text("From \(sourceDisplayName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating \(summary.displayName)")
                } else {
                    Toggle(
                        "Enabled",
                        isOn: Binding(
                            get: { summary.isEnabled },
                            set: { isEnabled in
                                setEnabled(isEnabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .accessibilityLabel("\(summary.displayName) Enabled")
                }
            }
        }
        .padding(.vertical, CrestSpacing.extraSmall)
    }
}

#Preview("Extension Row", traits: .fixedLayout(width: 560, height: 180)) {
    List {
        BrowserExtensionRow(
            summary: BrowserExtensionsPreviewFixture.summary,
            spaceID: BrowserExtensionsPreviewFixture.space.id,
            extensionControllerPool: BrowserExtensionsPreviewFixture.pool,
            platformActions: .none,
            isBusy: false,
            setEnabled: { _ in },
            setPermissionDecision: { _, _ in },
            setHostDecision: { _, _ in },
            requestRemoval: {}
        )
    }
}
