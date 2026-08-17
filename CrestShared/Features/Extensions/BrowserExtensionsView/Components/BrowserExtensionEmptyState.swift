import SwiftUI

struct BrowserExtensionEmptyState: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text("No Extensions Installed")
                    .font(.body.weight(.medium))
                Text("Add an extension below to review its access before use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "puzzlepiece.extension")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, CrestSpacing.small)
    }
}
