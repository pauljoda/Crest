import SwiftUI

/// Where the password is about to go, said before it goes there.
struct BrowserCredentialSaveDestination: View {
    let destination: BrowserCredentialPromptDestinationMetadata
    let space: BrowserSpaceIdentity?
    let namesSystemPasswordsDestination: Bool
    let isBusy: Bool
    /// Sends this one save to the other place; nil when there is no other.
    let switchDestination: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let note = destination.neverSavesNote {
            VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.destinationSpacing) {
                Label(destination.detail, systemImage: "lock")
                Text(note)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: BrowserCredentialPromptMetrics.destinationSpacing) {
            HStack(spacing: BrowserCredentialPromptMetrics.destinationSpacing) {
                detail
                if let syncStatus = destination.syncStatus {
                    Text("·")
                    Label(syncStatus, systemImage: "icloud")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let switchDestination, let switchTitle = destination.switchTitle {
                Spacer(minLength: 0)
                Button(action: switchDestination) {
                    Text(switchTitle)
                        .font(.caption)
                        .padding(.horizontal, CrestSpacing.small)
                        .padding(.vertical, CrestSpacing.extraSmall)
                }
                .buttonStyle(CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.compact))
                .disabled(isBusy)
            }
        }
    }

    /// The Space's own crest, unless the sentence beside it is already about
    /// iCloud, or there is no Space to draw.
    @ViewBuilder
    private var detail: some View {
        if namesSystemPasswordsDestination {
            Label(destination.detail, systemImage: "icloud")
        } else if let space {
            BrowserSpaceIdentityLabel(
                space: space,
                title: String(localized: destination.detail),
                iconSize: BrowserCredentialPromptMetrics.destinationIconSize
            )
        } else {
            Label(destination.detail, systemImage: "square.grid.2x2")
        }
    }
}
