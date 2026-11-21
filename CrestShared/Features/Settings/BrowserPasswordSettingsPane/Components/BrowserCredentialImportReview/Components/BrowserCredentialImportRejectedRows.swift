import SwiftUI

struct BrowserCredentialImportRejectedRows: View {
    let rejections: [CredentialRowRejection]

    private var visibleRejections: [CredentialRowRejection] {
        Array(rejections.prefix(BrowserCredentialImportReviewMetrics.maximumVisibleRejections))
    }

    var body: some View {
        CrestSettingsGroup(
            "Rejected rows",
            footnote: "These rows are excluded from the import. Correct the source file to import them later."
        ) {
            ForEach(visibleRejections, id: \.rowNumber) { rejection in
                BrowserCredentialImportNoticeRow(
                    rowNumber: rejection.rowNumber,
                    message: String(localized: rejection.flaw.message),
                    tint: CrestColor.danger,
                    fill: CrestColor.dangerFill
                )
            }

            if rejections.count > visibleRejections.count {
                Text(
                    "\(rejections.count - visibleRejections.count) additional rejected rows are included in the final count."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
