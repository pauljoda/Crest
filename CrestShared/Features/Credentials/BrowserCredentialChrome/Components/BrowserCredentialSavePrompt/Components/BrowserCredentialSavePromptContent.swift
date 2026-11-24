import SwiftUI

/// What the save prompt shows. A pointer shell draws a card: what it asks and
/// for which account, then the Space it saves in beside the answers. A touch
/// shell draws a band: the header, where the password goes, and the answers on
/// a row of their own.
struct BrowserCredentialSavePromptContent: View {
    let candidate: BrowserCredentialSaveCandidate
    let route: BrowserCredentialPromptRoute
    let destination: BrowserCredentialPromptDestinationMetadata
    let space: BrowserSpaceIdentity?
    let namesSystemPasswordsDestination: Bool
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void
    let neverSave: () -> Void
    let perform: (BrowserCredentialPromptPrimaryAction) -> Void

    @ViewBuilder
    var body: some View {
        if metrics.surfaceStyle == .panel {
            card
        } else {
            band
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.savePromptContentSpacing) {
            HStack(alignment: .top, spacing: BrowserCredentialPromptMetrics.headerSpacing) {
                CrestIconTile(
                    systemImage: route.primaryAction?.action?.symbol ?? BrowserCredentialSavePromptAction.create.symbol,
                    color: CrestBrandTheme.accent,
                    size: BrowserCredentialPromptMetrics.headerIdentitySize,
                    symbolSize: BrowserCredentialPromptMetrics.headerIdentitySymbolSize
                )
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.headerTextSpacing) {
                    Text(route.title(spaceName: space?.name))
                        .font(CrestTypography.display(15, relativeTo: .headline))
                    Text("\(candidate.username) · \(candidate.origin.host)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            notes
            HStack(spacing: BrowserCredentialPromptMetrics.saveActionSpacing) {
                moreMenu
                if let space {
                    BrowserSpaceIdentityLabel(
                        identity: space, iconSize: BrowserCredentialPromptMetrics.destinationIconSize
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: BrowserCredentialPromptMetrics.saveHeaderSpacerLength)
                BrowserCredentialSaveActions(
                    route: route,
                    space: space,
                    metrics: metrics,
                    isStacked: false,
                    dismiss: dismiss,
                    perform: perform
                )
            }
        }
    }

    private var band: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserCredentialPromptMetrics.savePromptContentSpacing
        ) {
            BrowserCredentialSavePromptHeader(
                candidate: candidate,
                route: route,
                space: space,
                metrics: metrics,
                dismiss: dismiss,
                perform: perform
            )
            BrowserCredentialSaveDestination(
                destination: destination,
                space: space,
                namesSystemPasswordsDestination: namesSystemPasswordsDestination
            )
            notes
            if metrics.saveActionPlacement == .belowContent {
                HStack(spacing: BrowserCredentialPromptMetrics.saveActionSpacing) {
                    moreMenu
                    BrowserCredentialSaveActionRow(
                        route: route,
                        space: space,
                        metrics: metrics,
                        dismiss: dismiss,
                        perform: perform
                    )
                }
            }
        }
    }

    /// What else the person can answer: never to be asked on this site.
    @ViewBuilder
    private var moreMenu: some View {
        if route.dismissAction.holdsCandidate {
            Menu {
                Button("Never for This Site", systemImage: "hand.raised", action: neverSave)
                    .accessibilityIdentifier("crest-password-save-never")
                    .crestMenuActionLabelStyle()
            } label: {
                Image(systemName: "ellipsis")
                    .frame(
                        width: BrowserCredentialPromptMetrics.saveMoreMenuSize,
                        height: BrowserCredentialPromptMetrics.saveMoreMenuSize
                    )
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(CrestChromeButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
            .help("More")
        }
    }

    /// What the prompt adds when it must: that the form came from another
    /// site, or that saving failed.
    @ViewBuilder
    private var notes: some View {
        if candidate.isCrossOriginFrame {
            Text(
                route.crossOriginMessage(
                    frameOrigin: candidate.origin,
                    topLevelOrigin: candidate.topLevelOrigin,
                    subject: metrics.saveCrossOriginSubject
                )
            )
            .font(.caption)
            .foregroundStyle(CrestColor.warning)
        }
        if let errorMessage = route.errorMessage(spaceName: space?.name) {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(CrestColor.danger)
        }
    }
}
