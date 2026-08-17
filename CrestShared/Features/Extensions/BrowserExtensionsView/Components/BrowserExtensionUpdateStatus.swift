import SwiftUI

struct BrowserExtensionUpdateStatus: View {
    let model: BrowserExtensionUpdateModel

    @ViewBuilder
    var body: some View {
        if model.isChecking {
            HStack(spacing: BrowserExtensionsMetrics.updateStatusSpacing) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for extension updates…")
                    .foregroundStyle(.secondary)
            }
        } else if let error = model.lastErrorDescription {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        } else if let checkedAt = model.lastCheckedAt {
            LabeledContent {
                Text(
                    checkedAt,
                    format: .dateTime.month().day().year().hour().minute()
                )
            } label: {
                Text("Last Checked")
                if let appliedSummary {
                    Text(appliedSummary)
                }
            }
        }
    }

    private var appliedSummary: String? {
        let names = model.lastUpdatedExtensionNames
        guard let onlyName = names.first else { return nil }
        guard names.count > 1 else {
            return String(localized: "Updated \(onlyName)")
        }
        return String(localized: "Updated \(names.count) extensions")
    }
}
