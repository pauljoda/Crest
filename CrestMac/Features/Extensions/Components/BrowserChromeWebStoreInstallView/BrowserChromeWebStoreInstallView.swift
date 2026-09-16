import SwiftUI

struct BrowserChromeWebStoreInstallView: View {
    let page: BrowserPage

    private let phaseOverride: BrowserChromeWebStoreInstallPhase?

    @State private var isAccessExpanded = true
    @State private var isSelectingSpaces = false
    @State private var accessReview = BrowserExtensionInstallationPermissionPolicy.Review()

    init(page: BrowserPage) {
        self.page = page
        phaseOverride = nil
    }

    init(
        page: BrowserPage,
        phase: BrowserChromeWebStoreInstallPhase
    ) {
        self.page = page
        phaseOverride = phase
    }

    var body: some View {
        let phase = resolvedPhase
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            if isSelectingSpaces, let candidate = resolvedPhase.candidate {
                BrowserExtensionInstallSpacesPage(
                    primarySpaceName: page.chromeWebStoreInstallSpaceName,
                    spaces: page.additionalExtensionSpaces(candidate.id),
                    selection: $accessReview.additionalSpaceIDs,
                    goBack: { isSelectingSpaces = false })
            } else {
                BrowserChromeWebStoreInstallHeader(
                    phase: phase,
                    spaceID: page.spaceID
                )

                switch phase {
                case .unavailable:
                    EmptyView()
                case .preparing:
                    BrowserChromeWebStorePreparingContent()
                case .installed(let name):
                    BrowserExtensionInstallCompletionContent(
                        name: name,
                        spaceName: page.chromeWebStoreInstallSpaceName,
                        compatibilityIssues:
                            page.installedChromeWebStoreCompatibilityIssues,
                        additionalSpaceCount: page.installedChromeWebStoreAdditionalSpaceCount,
                        copyWarnings: page.installedChromeWebStoreCopyWarnings
                    )
                case .review(let candidate, let errorDescription):
                    BrowserChromeWebStoreReviewContent(
                        candidate: candidate,
                        spaceName: page.chromeWebStoreInstallSpaceName,
                        errorDescription: errorDescription,
                        isAccessExpanded: $isAccessExpanded,
                        accessReview: $accessReview
                    )
                case .failed(let error):
                    BrowserExtensionInstallErrorContent(error: error)
                }

                if resolvedPhase.candidate != nil {
                    Button("Install in other Spaces…") { isSelectingSpaces = true }
                        .disabled(page.isInstallingChromeWebStoreExtension)
                    if !accessReview.additionalSpaceIDs.isEmpty {
                        Text("Additional Spaces: \(accessReview.additionalSpaceIDs.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                BrowserChromeWebStoreInstallActions(page: page, phase: phase, accessReview: accessReview)
            }
        }
        .onChange(of: resolvedPhase.candidate?.id, initial: true) {
            if let candidate = resolvedPhase.candidate { accessReview = candidate.accessReview }
        }
        .padding(CrestSpacing.extraLarge)
        .frame(width: BrowserExtensionInstallMetrics.width)
        .interactiveDismissDisabled(page.isInstallingChromeWebStoreExtension)
    }

    private var resolvedPhase: BrowserChromeWebStoreInstallPhase {
        phaseOverride
            ?? BrowserChromeWebStoreInstallPhase.resolve(
                isPreparing: page.isPreparingChromeWebStoreExtension,
                installedName: page.installedChromeWebStoreExtensionName,
                candidate: page.chromeWebStoreCandidate,
                errorDescription: page.chromeWebStoreInstallErrorDescription
            )
    }
}
