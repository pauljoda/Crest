import SwiftUI

struct BrowserMozillaAddonsInstallView: View {
    let session: BrowserMozillaAddonsInstallSession

    private let phaseOverride: BrowserMozillaAddonsInstallPhase?

    @State private var isAccessExpanded = true
    @State private var isSelectingSpaces = false
    @State private var accessReview = BrowserExtensionInstallationPermissionPolicy.Review()

    init(session: BrowserMozillaAddonsInstallSession) {
        self.session = session
        phaseOverride = nil
    }

    init(
        session: BrowserMozillaAddonsInstallSession,
        phase: BrowserMozillaAddonsInstallPhase
    ) {
        self.session = session
        phaseOverride = phase
    }

    var body: some View {
        let phase = phaseOverride ?? session.phase
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            if isSelectingSpaces, let candidate = (phaseOverride ?? session.phase).candidate {
                BrowserExtensionInstallSpacesPage(
                    primarySpaceName: session.spaceName, spaces: session.additionalSpaces(candidate.id),
                    selection: $accessReview.additionalSpaceIDs,
                    goBack: { isSelectingSpaces = false })
            } else {
                BrowserMozillaAddonsInstallHeader(
                    phase: phase,
                    spaceID: session.spaceID
                )

                switch phase {
                case .unavailable:
                    EmptyView()
                case .preparing:
                    BrowserMozillaAddonsPreparingContent()
                case .installed(let name):
                    BrowserExtensionInstallCompletionContent(
                        name: name,
                        spaceName: session.spaceName,
                        compatibilityIssues:
                            session.installedCompatibilityIssues,
                        additionalSpaceCount: session.installedAdditionalSpaceCount,
                        copyWarnings: session.installedCopyWarnings
                    )
                case .review(let candidate, let errorDescription):
                    BrowserMozillaAddonsReviewContent(
                        candidate: candidate,
                        spaceName: session.spaceName,
                        errorDescription: errorDescription,
                        isAccessExpanded: $isAccessExpanded,
                        accessReview: $accessReview
                    )
                case .failed(let error):
                    BrowserExtensionInstallErrorContent(error: error)
                }

                if (phaseOverride ?? session.phase).candidate != nil {
                    Button("Install in other Spaces…") { isSelectingSpaces = true }
                        .disabled(session.isInstalling)
                    if !accessReview.additionalSpaceIDs.isEmpty {
                        Text("Additional Spaces: \(accessReview.additionalSpaceIDs.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                BrowserMozillaAddonsInstallActions(
                    session: session,
                    phase: phase,
                    accessReview: accessReview
                )
            }
        }
        .onChange(of: (phaseOverride ?? session.phase).candidate?.id, initial: true) {
            if let candidate = (phaseOverride ?? session.phase).candidate { accessReview = candidate.accessReview }
        }
        .padding(CrestSpacing.extraLarge)
        .frame(width: BrowserExtensionInstallMetrics.width)
        .interactiveDismissDisabled(session.isInstalling)
    }
}
