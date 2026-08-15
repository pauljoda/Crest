import SwiftUI

/// One saved password, as settings shows it: who it is for, where it signs in, how
/// narrowly it is scoped, and whether it synchronizes.
///
/// The shells' two copies of this row differed in three ways that were all
/// accidental — the desktop had a tooltip, touch had a wider hit target, and only the
/// desktop showed a row mid-delete. The tooltip and the hit target are platform
/// truths that `CrestControls` already resolves per platform; the progress state was
/// simply missing on touch and is here now.
struct BrowserPasswordDescriptorRow: View {
    let descriptor: CredentialDescriptor
    let space: BrowserSpace?
    var isDeleting = false
    let showDetails: () -> Void
    let requestDeletion: () -> Void

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: "key.fill")
                .foregroundStyle(space?.accent.color ?? CrestBrandTheme.accent)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CrestFormRowMetrics.titleSpacing) {
                Text(descriptor.displayName ?? descriptor.username)
                    .font(CrestTypography.controlTitle)
                    .lineLimit(1)
                if descriptor.displayName != nil {
                    Text(descriptor.username)
                        .font(CrestTypography.metadata)
                        .foregroundStyle(CrestColor.textSecondary)
                        .lineLimit(1)
                }
                Text(descriptor.origin.description)
                    .font(CrestTypography.metadata)
                    .foregroundStyle(CrestColor.textSecondary)
                    .lineLimit(1)
                if let scopeLabel = descriptor.scope.settingsLabel {
                    Text(scopeLabel)
                        .font(CrestTypography.compactMetadata)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: CrestSpacing.small)

            if descriptor.isSynchronizable {
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
                    .help("Synchronized through Crest’s iCloud Keychain item")
                    .accessibilityLabel("iCloud synchronization on")
            }

            if isDeleting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("View Password", systemImage: "eye", action: showDetails)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.crestIcon())

                Button(
                    "Delete Password",
                    systemImage: "trash",
                    role: .destructive,
                    action: requestDeletion
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.crestIcon(tint: .red))
            }
        }
        .frame(minHeight: CrestFormRowMetrics.minimumHeight)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Password Descriptor") {
    BrowserPasswordDescriptorRow(
        descriptor: BrowserCredentialDetailPreviewFixture.descriptor,
        space: nil,
        showDetails: {},
        requestDeletion: {}
    )
    .padding()
    .frame(width: 420)
}
