import SwiftUI

struct BrowserExtensionInstallAccessGroup: View {
    let title: String
    let values: [String]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text("\(title) (\(values.count))")
                .font(.caption.weight(.semibold))
            if values.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }
}

#Preview("Extension Install Access Group", traits: .sizeThatFitsLayout) {
    BrowserExtensionInstallAccessGroup(
        title: "Permissions",
        values: ["storage", "tabs"],
        emptyText: "No additional browser permissions requested."
    )
    .padding()
}
