import SwiftUI

struct BrowserWebPageSurface: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pagePresentation: BrowserPagePresentation

    var body: some View {
        ZStack(alignment: .top) {
            BrowserPlatformWebView(page: page)
                .accessibilityLabel(page.title.isEmpty ? "Web page" : page.title)

            if page.isFindPresented {
                BrowserFindBar(page: page)
                    .padding(BrowserWebPageSurfaceMetrics.overlayPadding)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topTrailing
                    )
            }

            BrowserWebPageFailureOverlay(
                page: page,
                branding: browser.selectedSpace?.branding,
                pagePresentation: pagePresentation
            )

            BrowserCredentialChrome(
                presentation: BrowserCredentialChromePresentation.resolve(
                    saveCandidate: page.credentialSaveCandidate,
                    fillRequest: page.credentialFillRequest
                ),
                page: page,
                browser: browser
            )
            .padding(BrowserWebPageSurfaceMetrics.overlayPadding)

            if page.isRegionCapturePresented {
                BrowserRegionCaptureOverlay(page: page)
                    .zIndex(BrowserWebPageSurfaceMetrics.regionCaptureZIndex)
            }

            if let feedback = page.developerCaptureFeedback {
                BrowserDeveloperCaptureFeedbackView(feedback: feedback)
                    .zIndex(BrowserWebPageSurfaceMetrics.feedbackZIndex)
            }
        }
    }
}
