import SwiftUI

struct BrowserCredentialImportNoticeRow: View {
    let rowNumber: Int
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.medium) {
            Text("Row \(rowNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(
                    minWidth: BrowserCredentialImportReviewMetrics.rowNumberWidth,
                    alignment: .leading
                )
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, CrestSpacing.medium)
    }
}
