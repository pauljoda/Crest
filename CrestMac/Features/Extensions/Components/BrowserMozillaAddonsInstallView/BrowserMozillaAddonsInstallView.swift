import SwiftUI

struct BrowserMozillaAddonsInstallView: View {
    let session: BrowserMozillaAddonsInstallSession

    private let phaseOverride: BrowserMozillaAddonsInstallPhase?

    @State private var isAccessExpanded = true

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
                        session.installedCompatibilityIssues
                )
            case .review(let candidate, let errorDescription):
                BrowserMozillaAddonsReviewContent(
                    candidate: candidate,
                    spaceName: session.spaceName,
                    errorDescription: errorDescription,
                    isAccessExpanded: $isAccessExpanded
                )
            case .failed(let error):
                BrowserExtensionInstallErrorContent(error: error)
            }

            Divider()
            BrowserMozillaAddonsInstallActions(
                session: session,
                phase: phase
            )
        }
        .padding(CrestSpacing.extraLarge)
        .frame(width: BrowserExtensionInstallMetrics.width)
        .interactiveDismissDisabled(session.isInstalling)
    }
}

#Preview("Firefox Add-ons Install — Review") {
    BrowserMozillaAddonsInstallView(
        session: BrowserMozillaAddonsInstallPreviewFixture.makeSession(),
        phase: .review(
            BrowserMozillaAddonsInstallPreviewFixture.candidate,
            errorDescription: nil
        )
    )
}
