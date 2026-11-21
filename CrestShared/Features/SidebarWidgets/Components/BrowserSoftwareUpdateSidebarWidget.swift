import SwiftUI

struct BrowserSoftwareUpdateSidebarWidget: View {
    // MARK: - Variables

    let instance: BrowserSidebarWidgetInstance
    let update: BrowserSoftwareUpdateWidgetSnapshot
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void

    @Environment(\.browserSoftwareUpdateReleasePage) private var openReleasePage

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserSidebarWidgetDeckStyle.contentSpacing) {
            headerRow
            progressZone
            actions
        }
        .overlay(alignment: .topTrailing) {
            hideButton
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crest software update")
    }

    private var canHide: Bool {
        instance.availableActions.contains(.hideSoftwareUpdate)
    }

    /// The card's own buttons, in the order their actions stand, without the
    /// corner control that hides it.
    private var buttonActions: [BrowserSidebarWidgetAction] {
        instance.availableActions.filter { $0.cardButton != nil }
            .sorted { ($0.cardButton?.priority ?? 0) < ($1.cardButton?.priority ?? 0) }
    }

    // MARK: - Actions - Layout

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
                                CrestColor.warningFill,
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

                if let version = update.version, let openReleasePage {
                    Button("What's New") { openReleasePage(version: version) }
                        .buttonStyle(.plain)
                        .font(CrestTypography.metadata.weight(.medium))
                        .foregroundStyle(CrestBrandTheme.accent)
                        .accessibilityLabel("Open the update's release notes")
                        .help("Open the update's release notes")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(
                .trailing,
                canHide ? BrowserSidebarWidgetDeckStyle.quietControlDiameter + CrestSpacing.extraSmall : 0
            )
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var hideButton: some View {
        if canHide {
            Button {
                perform(.hideSoftwareUpdate, instance.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle(alignment: .topTrailing))
            .accessibilityLabel("Hide Update")
            .help("Hide until you check for updates")
        }
    }

    @ViewBuilder
    private var progressZone: some View {
        if let progress = update.progress, update.phase.isTransferring {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(CrestBrandTheme.accent)
                .accessibilityLabel(Text(statusLabel))
        } else if update.phase.isWorking {
            HStack(spacing: CrestSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text(statusLabel)
                    .font(CrestTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(statusLabel))
        }

        if let message = update.message, update.phase.showsMessage {
            Text(verbatim: message)
                .font(CrestTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !buttonActions.isEmpty {
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

    /// Each button the card offers, in order, the first prominent one as the
    /// card's primary button.
    @ViewBuilder
    private var actionButtons: some View {
        let primary = buttonActions.first { $0.cardButton?.isProminent == true }
        ForEach(buttonActions, id: \.self) { action in
            if let button = action.cardButton {
                actionButton(action, button, emphasis: action == primary ? .prominent : .quiet)
            }
        }
    }

    /// The card's button for `action`, as `button` shows it: a link to the
    /// update's release page, or a button that performs it.
    @ViewBuilder
    private func actionButton(
        _ action: BrowserSidebarWidgetAction,
        _ button: BrowserSidebarWidgetAction.CardButton,
        emphasis: BrowserSidebarWidgetActionEmphasis
    ) -> some View {
        let label = Label {
            Text(button.title)
        } icon: {
            Image(systemName: button.symbol)
        }
        if button.opensReleasePage {
            if let informationURL = update.informationURL {
                Link(destination: informationURL) { label }
                    .buttonStyle(BrowserSidebarWidgetActionButtonStyle(emphasis: emphasis))
            }
        } else {
            Button {
                perform(action, instance.id)
            } label: {
                label
            }
            .buttonStyle(BrowserSidebarWidgetActionButtonStyle(emphasis: emphasis))
            .accessibilityLabel(Text(button.accessibilityLabel ?? button.title))
            .help(Text(button.accessibilityLabel ?? button.title))
        }
    }

    private var headerTitle: Text {
        update.phase.isTitledByUpdate ? Text(verbatim: update.title) : Text(update.phase.title)
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

    private var statusLabel: LocalizedStringResource {
        (update.isInformationOnly ? update.phase.informationOnlyStatusLabel : nil) ?? update.phase.statusLabel
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
    /// Opens the release page of the update a card presents. Nil where the
    /// shell has no window to open it in, which leaves out What's New.
    @Entry var browserSoftwareUpdateReleasePage: BrowserSoftwareUpdateReleasePageAction? = nil
}
