import SwiftUI

/// The Space the passwords go into, in the review's first group, with the
/// promise about where they are kept beneath it.
struct BrowserCredentialImportDestinationCard: View {
    let space: BrowserSpaceIdentity
    let format: CredentialFileFormat

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: CrestSpacing.large) {
                BrowserSpaceIdentityIcon(
                    identity: space, size: BrowserCredentialImportReviewMetrics.destinationIconSize
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    Text("Importing into")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(space.name)
                        .font(.title3.weight(.semibold))
                    Text(
                        "Every accepted credential will be stored only in this Space’s Keychain inventory."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: CrestSpacing.small)

                Label {
                    Text(format.title)
                } icon: {
                    Image(systemName: "doc.text")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } footer: {
            Label(
                "Passwords remain encrypted in this Space’s Keychain and never appear in logs, notifications, or diagnostics.",
                systemImage: "lock.shield.fill"
            )
            .crestFormFootnote()
        }
    }
}
