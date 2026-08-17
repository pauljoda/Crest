import SwiftUI

struct BrowserSourceImportSpaceHeader: View {
    let application: BrowserImportApplication?
    let space: BrowserSpace

    @ViewBuilder
    var body: some View {
        if application?.sourceSpaceHeaderStyle == .sectionLabel {
            HStack {
                Text(space.name)
                    .font(.callout.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(height: 36)
        } else {
            HStack(spacing: 8) {
                BrowserSpaceIdentityIcon(space: space, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(space.name)
                        .font(.callout.weight(.semibold))
                    Text(application?.name ?? "Browser")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .frame(height: 44)
        }
    }
}
