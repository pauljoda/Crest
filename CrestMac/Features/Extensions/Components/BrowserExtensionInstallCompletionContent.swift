import SwiftUI

struct BrowserExtensionInstallCompletionContent: View {
    let name: String
    let spaceName: String
    let compatibilityIssues: [String]

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text(statusTitle)
                    .font(.body.weight(.medium))
                Text(
                    "It is enabled only in the \(spaceName) Space. You can manage it from Extensions settings."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(compatibilityIssues, id: \.self) { issue in
                    Text(issue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: statusSymbolName)
                .foregroundStyle(statusColor)
        }
    }

    private var statusTitle: String {
        compatibilityIssues.isEmpty
            ? "\(name) was added to Crest"
            : "\(name) was added with limited compatibility"
    }

    private var statusSymbolName: String {
        compatibilityIssues.isEmpty
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        compatibilityIssues.isEmpty ? .green : .orange
    }
}

#Preview("Extension Install — Completed", traits: .sizeThatFitsLayout) {
    BrowserExtensionInstallCompletionContent(
        name: "Reading Focus",
        spaceName: "Research",
        compatibilityIssues: [
            "Some extension features are unavailable in this Crest build."
        ]
    )
    .padding()
}
