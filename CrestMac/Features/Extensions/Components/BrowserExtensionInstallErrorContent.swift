import SwiftUI

struct BrowserExtensionInstallErrorContent: View {
    let error: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text("Crest couldn’t prepare this extension")
                    .font(.body.weight(.medium))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

#Preview("Extension Install — Error", traits: .sizeThatFitsLayout) {
    BrowserExtensionInstallErrorContent(
        error: "The package could not be verified."
    )
    .padding()
}
