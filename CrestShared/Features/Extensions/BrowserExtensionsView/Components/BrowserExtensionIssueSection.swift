import SwiftUI

struct BrowserExtensionIssueSection: View {
    let issue: BrowserExtensionIssuePresentation
    @State private var isTechnicalDetailsExpanded = false

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
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: toggleTechnicalDetails) {
                        HStack(spacing: CrestSpacing.small) {
                            Image(
                                systemName: isTechnicalDetailsExpanded
                                    ? "chevron.down"
                                    : "chevron.right"
                            )
                            .font(.system(size: 9, weight: .semibold))

                            Text("Technical Details")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Technical Details")
                    .accessibilityValue(
                        isTechnicalDetailsExpanded ? "Expanded" : "Collapsed"
                    )

                    if isTechnicalDetailsExpanded {
                        BrowserExtensionValueList(
                            title: "Reported by the extension",
                            values: issue.technicalDetails,
                            symbol: "chevron.left.forwardslash.chevron.right"
                        )
                        .padding(.top, CrestSpacing.extraSmall)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleTechnicalDetails() {
        withAnimation {
            isTechnicalDetailsExpanded.toggle()
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
