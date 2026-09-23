import SwiftUI

struct BrowserSoftwareUpdateSidebarWidget: View {
    let instance: BrowserSidebarWidgetInstance
    let update: BrowserSoftwareUpdateWidgetSnapshot
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void

    @Environment(\.browserSoftwareUpdateDetails) private var showDetails

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserSidebarWidgetDeckStyle.contentSpacing) {
            headerRow
            progressZone
            actions
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crest software update")
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: CrestSpacing.small) {
            BrowserSoftwareUpdateApplicationIcon()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                HStack(spacing: CrestSpacing.extraSmall) {
                    headerTitle
                        .font(.subheadline.weight(.semibold))
                    if update.isFixture {
                        Text("TEST")
                            .font(CrestTypography.badge)
                            .padding(.horizontal, CrestSpacing.extraSmall)
                            .padding(
                                .vertical,
                                BrowserSidebarWidgetDeckStyle.badgeVerticalPadding
                            )
                            .background(
                                .orange.opacity(CrestOpacity.brandHairline),
                                in: .capsule
                            )
                            .accessibilityLabel("Test fixture")
                    }
                }
                .lineLimit(1)

                if let versionLine {
                    Text(verbatim: versionLine)
                        .font(CrestTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if hasDetails, let showDetails {
                    Button("What's New", action: showDetails)
                        .buttonStyle(.plain)
                        .font(CrestTypography.metadata.weight(.medium))
                        .foregroundStyle(CrestBrandTheme.accent)
                        .accessibilityLabel("Review update details")
                        .help("Review update details")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var progressZone: some View {
        if let progress = update.progress, isTransferring {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(CrestBrandTheme.accent)
                .accessibilityLabel(statusLabel)
        } else if isTransferring || update.phase == .checking
            || update.phase == .installing
        {
            HStack(spacing: CrestSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text(verbatim: statusLabel)
                    .font(CrestTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statusLabel)
        }

        if let message = update.message, showsMessage {
            Text(verbatim: message)
                .font(CrestTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !instance.availableActions.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CrestSpacing.small) {
                    actionButtons
                }
                VStack(spacing: CrestSpacing.small) {
                    actionButtons
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if instance.availableActions.contains(.declineAutomaticUpdateChecks) {
            actionButton(
                .declineAutomaticUpdateChecks,
                label: "Not Now",
                symbol: "clock",
                emphasis: .quiet
            )
        }

        if instance.availableActions.contains(.dismissExactUpdate) {
            actionButton(
                .dismissExactUpdate,
                label: "Skip",
                symbol: "forward.end",
                accessibilityLabel: "Skip This Version",
                emphasis: .quiet
            )
        }

        if instance.availableActions.contains(.viewUpdateInformation),
            let informationURL = update.informationURL
        {
            Link(destination: informationURL) {
                Label("View Release", systemImage: "arrow.up.right")
            }
            .buttonStyle(
                BrowserSidebarWidgetActionButtonStyle(
                    emphasis: .prominent
                )
            )
        } else if instance.availableActions.contains(.installUpdate) {
            actionButton(
                .installUpdate,
                label: "Download",
                symbol: "arrow.down.circle",
                accessibilityLabel: "Download Update",
                emphasis: .prominent
            )
        } else if instance.availableActions.contains(.installAndRelaunch) {
            actionButton(
                .installAndRelaunch,
                label: "Restart",
                symbol: "arrow.down.to.line",
                accessibilityLabel: "Restart and Update",
                emphasis: .prominent
            )
        } else if instance.availableActions.contains(.cancelUpdate) {
            actionButton(
                .cancelUpdate,
                label: "Cancel",
                symbol: "xmark",
                emphasis: .quiet
            )
        } else if instance.availableActions.contains(.retryUpdateInstallation) {
            actionButton(
                .retryUpdateInstallation,
                label: "Retry",
                symbol: "arrow.clockwise",
                accessibilityLabel: "Try Quitting Again",
                emphasis: .prominent
            )
        } else if instance.availableActions.contains(.enableAutomaticUpdateChecks) {
            actionButton(
                .enableAutomaticUpdateChecks,
                label: "Check Automatically",
                symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                emphasis: .prominent
            )
        } else if instance.availableActions.contains(.acknowledgeUpdateStatus) {
            actionButton(
                .acknowledgeUpdateStatus,
                label: "Dismiss",
                symbol: "xmark",
                emphasis: .quiet
            )
        }
    }

    private func actionButton(
        _ action: BrowserSidebarWidgetAction,
        label: LocalizedStringKey,
        symbol: String,
        accessibilityLabel: LocalizedStringKey? = nil,
        emphasis: BrowserSidebarWidgetActionEmphasis
    ) -> some View {
        Button {
            perform(action, instance.id)
        } label: {
            Label(label, systemImage: symbol)
        }
        .buttonStyle(BrowserSidebarWidgetActionButtonStyle(emphasis: emphasis))
        .accessibilityLabel(accessibilityLabel ?? label)
        .help(accessibilityLabel ?? label)
    }

    private var isTransferring: Bool {
        update.phase == .downloading || update.phase == .extracting
    }

    private var hasDetails: Bool {
        if let releaseNotes = update.releaseNotes, !releaseNotes.isEmpty {
            return true
        }
        return update.informationURL != nil
    }

    private var headerTitle: Text {
        switch update.phase {
        case .permission: Text("Keep Crest Up to Date")
        case .checking: Text("Checking for Updates")
        case .available: Text(verbatim: update.title)
        case .downloading: Text("Downloading Update")
        case .extracting: Text("Preparing Update")
        case .readyToInstall: Text("Ready to Install")
        case .installing: Text("Installing Update")
        case .upToDate: Text("Crest Is Up to Date")
        case .failed: Text("Update Check Failed")
        case .installed: Text("Update Installed")
        case .unavailable: Text("Software Update Unavailable")
        }
    }

    private var showsMessage: Bool {
        switch update.phase {
        case .checking, .downloading, .extracting:
            false
        default:
            true
        }
    }

    private var versionLine: String? {
        switch (update.version, update.build) {
        case (let version?, let build?) where version != build:
            "Version \(version) · Build \(build)"
        case (let version?, _):
            "Version \(version)"
        case (_, let build?):
            "Build \(build)"
        default:
            nil
        }
    }

    private var statusLabel: String {
        switch update.phase {
        case .permission: "Permission required"
        case .checking: "Checking"
        case .available: update.isInformationOnly ? "Website release" : "Ready to download"
        case .downloading: "Downloading"
        case .extracting: "Preparing"
        case .readyToInstall: "Ready to install"
        case .installing: "Installing"
        case .upToDate: "Up to date"
        case .failed: "Update error"
        case .installed: "Installed"
        case .unavailable: "Unavailable"
        }
    }
}

private struct BrowserSoftwareUpdateApplicationIcon: View {
    @Environment(\.browserApplicationIcon) private var applicationIcon

    var body: some View {
        (applicationIcon ?? Image(systemName: "app.fill"))
            .resizable()
            .scaledToFit()
            .frame(
                width: BrowserSidebarWidgetDeckStyle.headerTileSize,
                height: BrowserSidebarWidgetDeckStyle.headerTileSize
            )
    }
}

extension EnvironmentValues {
    /// Opens the full release notes for the update a card presents. Nil where
    /// the shell has no window to show them in, which leaves out What's New.
    @Entry var browserSoftwareUpdateDetails: (@MainActor () -> Void)? = nil
}
