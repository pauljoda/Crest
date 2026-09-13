import SwiftUI

struct BrowserExtensionInstallPreparingContent: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
