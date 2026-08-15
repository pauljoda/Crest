import SwiftUI

struct BrowserChromeWebStorePreparingContent: View {
    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text("Checking the extension…")
                    .font(.body.weight(.medium))
                Text(
                    "Crest is downloading the signed CRX3 package and verifying its developer and Web Store signatures."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Chrome Web Store Install — Preparing", traits: .sizeThatFitsLayout) {
    BrowserChromeWebStorePreparingContent()
        .padding()
}
