import SwiftUI

struct BrowserCredentialImportSummaryView: View {
    let plan: BrowserCredentialImportPlan

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserCredentialImportReviewSectionHeader(
                title: "Review",
                detail: "Confirm what Crest will change before anything is saved."
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: CrestSpacing.medium) {
                    metrics
                }
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: CrestSpacing.medium
                ) {
                    metrics
                }
            }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        BrowserCredentialImportMetric(
            title: "Ready to import",
            value: plan.proposedImportCount,
            systemImage: "checkmark.circle.fill",
            color: .green
        )
        BrowserCredentialImportMetric(
            title: "Need review",
            value: plan.conflictCount,
            systemImage: "arrow.triangle.branch",
            color: .orange
        )
        BrowserCredentialImportMetric(
            title: "Warnings",
            value: plan.warnings.count,
            systemImage: "exclamationmark.shield.fill",
            color: .orange
        )
        BrowserCredentialImportMetric(
            title: "Rejected rows",
            value: plan.rejections.count,
            systemImage: "xmark.octagon.fill",
            color: .red
        )
    }
}
