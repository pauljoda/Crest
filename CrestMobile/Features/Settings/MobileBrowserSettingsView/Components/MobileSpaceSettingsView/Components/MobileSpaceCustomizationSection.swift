import SwiftUI

struct MobileSpaceCustomizationSection: View {
    let space: SpaceModel
    let editAppearance: () -> Void

    var body: some View {
        Section("Appearance") {
            Button(action: editAppearance) {
                HStack(spacing: CrestSpacing.large) {
                    BrowserSpaceIdentityIcon(space: space, size: 44)
                    VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                        Text(space.settings.name).font(.headline)
                        Text("Name, crest, colors, and background").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: CrestSpacing.extraSmall)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, CrestSpacing.small)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(BrowserMobileAccessibilityID.spaceCustomize)
        }
    }

}
