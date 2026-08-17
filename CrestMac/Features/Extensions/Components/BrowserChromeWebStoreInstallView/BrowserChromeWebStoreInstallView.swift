import SwiftUI

struct BrowserChromeWebStoreInstallView: View {
    let page: BrowserPage

    private let phaseOverride: BrowserChromeWebStoreInstallPhase?

    @State private var isAccessExpanded = true

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
                        page.installedChromeWebStoreCompatibilityIssues
                )
            case .review(let candidate, let errorDescription):
                BrowserChromeWebStoreReviewContent(
                    candidate: candidate,
                    spaceName: page.chromeWebStoreInstallSpaceName,
                    errorDescription: errorDescription,
                    isAccessExpanded: $isAccessExpanded
                )
            case .failed(let error):
                BrowserExtensionInstallErrorContent(error: error)
            }

            Divider()
            BrowserChromeWebStoreInstallActions(page: page, phase: phase)
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
