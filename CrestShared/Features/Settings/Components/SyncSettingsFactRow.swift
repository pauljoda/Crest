import SwiftUI

struct SyncSettingsFactRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Sync Fact") {
    SyncSettingsFactRow(
        title: "Device-only data",
        detail: "Cookies, downloads, and active page state stay on this device.",
        symbol: "internaldrive.fill"
    )
    .padding()
}
