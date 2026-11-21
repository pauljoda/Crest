import SwiftUI

struct BrowserCredentialImportSummaryView: View {
    let review: BrowserCredentialImportReview

    var body: some View {
        CrestSettingsGroup("Review", footnote: "Confirm what Crest will change before anything is saved.") {
            BrowserCredentialImportMetric(
                title: "Ready to import",
                value: review.proposedImportCount,
                systemImage: "checkmark.circle.fill",
                color: CrestColor.success
            )
            BrowserCredentialImportMetric(
                title: "Need review",
                value: review.conflictCount,
                systemImage: "arrow.triangle.branch",
                color: CrestColor.warning
            )
            BrowserCredentialImportMetric(
                title: "Warnings",
                value: review.plan.warnings.count,
                systemImage: "exclamationmark.shield.fill",
                color: CrestColor.warning
            )
            BrowserCredentialImportMetric(
                title: "Rejected rows",
                value: review.plan.rejections.count,
                systemImage: "xmark.octagon.fill",
                color: CrestColor.danger
            )
        }
    }
}
