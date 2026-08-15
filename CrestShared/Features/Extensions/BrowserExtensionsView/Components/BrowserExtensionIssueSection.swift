import SwiftUI

struct BrowserExtensionIssueSection: View {
    let issue: BrowserExtensionIssuePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Label(issue.title, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text(issue.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !issue.technicalDetails.isEmpty {
                DisclosureGroup("Technical Details") {
                    BrowserExtensionValueList(
                        title: "Reported by the extension",
                        values: issue.technicalDetails,
                        symbol: "chevron.left.forwardslash.chevron.right"
                    )
                    .padding(.top, CrestSpacing.extraSmall)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Extension Issue", traits: .sizeThatFitsLayout) {
    BrowserExtensionIssueSection(
        issue: BrowserExtensionsPreviewFixture.issue
    )
    .frame(width: 420)
    .padding()
}
