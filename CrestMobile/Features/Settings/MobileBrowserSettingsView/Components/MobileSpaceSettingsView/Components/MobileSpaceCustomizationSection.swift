import SwiftUI

struct MobileSpaceCustomizationSection: View {
    let browser: BrowserStore
    let space: BrowserSpace
    let editAppearance: () -> Void

    var body: some View {
        Section("Appearance") {
            Button(action: editAppearance) {
                HStack(spacing: 16) {
                    BrowserSpaceIdentityIcon(space: browser.liveSpace(space), size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(browser.liveSpace(space).name).font(.headline)
                        Text("Name, crest, colors, and background").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mobile-space-customize")
        }
    }

    static func usesStableCompactLayout(for horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass != .regular
    }
}
