import SwiftUI

struct BrowserWebPageFailureOverlay: View {
    let page: BrowserPage
    let branding: BrowserSpaceBranding?
    let pagePresentation: BrowserPagePresentation

    var body: some View {
        switch pagePresentation {
        case .navigationFailure:
            if let failure = page.navigationFailure {
                BrowserNavigationFailureView(
                    failure: failure,
                    branding: branding,
                    layout: .regular,
                    canGoBack: page.canReturnFromNavigationFailure,
                    canProceed: page.canProceedAfterCertificateFailure,
                    retry: page.retryAfterNavigationFailure,
                    goBack: page.returnFromNavigationFailure,
                    proceed: page.proceedAfterCertificateFailure
                )
            }
        case .processFailure:
            BrowserNavigationFailureView(
                failure: .webContentProcessStopped(url: page.displayURL),
                branding: branding,
                layout: .regular,
                canGoBack: false,
                canProceed: false,
                retry: page.retryAfterProcessFailure,
                goBack: {},
                proceed: {}
            )
        case .noSelection, .startPage, .livePage, .unloaded, .automaticRestore:
            EmptyView()
        }
    }
}

#Preview("Browser Web Page Process Failure") {
    let preview = BrowserDetailPreviewFixture.makeWebContent()

    BrowserWebPageFailureOverlay(
        page: preview.page,
        branding: preview.browser.selectedSpace?.branding,
        pagePresentation: .processFailure
    )
    .frame(width: 720, height: 480)
}
