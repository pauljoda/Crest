import SwiftUI

struct BrowserMozillaAddonsPreparingContent: View {
    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text("Checking the add-on…")
                    .font(.body.weight(.medium))
                Text(
                    "Crest is downloading the add-on from Mozilla and checking it against the checksum, size, and identity Firefox Add-ons published for it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Firefox Add-ons Install — Preparing", traits: .sizeThatFitsLayout) {
    BrowserMozillaAddonsPreparingContent()
        .padding()
}
