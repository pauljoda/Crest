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

#if DEBUG
    #Preview("Component") {
        SyncSettingsFactRow(
            title: "Private by Space", detail: "Each Space keeps its browsing data separate.", symbol: "lock.shield"
        ).padding().frame(width: 380)
    }
#endif
