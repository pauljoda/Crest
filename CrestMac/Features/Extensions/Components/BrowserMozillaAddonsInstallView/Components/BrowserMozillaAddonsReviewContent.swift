import SwiftUI

struct BrowserMozillaAddonsReviewContent: View {
    let candidate: BrowserMozillaAddonsCandidate
    let spaceName: String
    let errorDescription: String?
    @Binding var isAccessExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            if let description = candidate.displayDescription {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent("Install In", value: "\(spaceName) Space")
                .font(.callout)
            if let version = candidate.version {
                LabeledContent("Version", value: version)
                    .font(.callout)
            }

            if let issue = candidate.compatibility.blockingIssues.first {
                Label {
                    VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                        Text("Not available in this Crest build")
                            .font(.callout.weight(.semibold))
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
            }

            DisclosureGroup(isExpanded: $isAccessExpanded) {
                ScrollView {
                    VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                        BrowserExtensionInstallAccessGroup(
                            title: "Permissions",
                            values: candidate.requestedPermissions,
                            emptyText: "No additional browser permissions requested."
                        )
                        BrowserExtensionInstallAccessGroup(
                            title: "Website Access",
                            values: candidate.requestedHosts,
                            emptyText: "No website access requested."
                        )
                        if !candidate.errors.isEmpty {
                            BrowserExtensionInstallAccessGroup(
                                title: "WebKit Compatibility Warnings",
                                values: candidate.errors,
                                emptyText: ""
                            )
                            .foregroundStyle(.orange)
                        }
                        if !candidate.compatibility.issues.isEmpty {
                            BrowserExtensionInstallAccessGroup(
                                title: "Crest Compatibility",
                                values: candidate.compatibility.issues.map(\.message),
                                emptyText: ""
                            )
                            .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(
                    maxHeight: BrowserExtensionInstallMetrics
                        .accessReviewMaximumHeight
                )
                .padding(.top, CrestSpacing.small)
            } label: {
                Label(
                    "Review Access and Compatibility",
                    systemImage: "hand.raised.fill"
                )
                .font(.callout.weight(.semibold))
            }

            if let errorDescription {
                Label(
                    errorDescription,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Firefox Add-ons Install — Access Review") {
    @Previewable @State var isAccessExpanded = true

    BrowserMozillaAddonsReviewContent(
        candidate: BrowserMozillaAddonsInstallPreviewFixture.candidate,
        spaceName: BrowserMozillaAddonsInstallPreviewFixture.spaceName,
        errorDescription: nil,
        isAccessExpanded: $isAccessExpanded
    )
    .padding()
    .frame(width: BrowserExtensionInstallMetrics.width)
}
