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
                BrowserFindBar(port: findPort, capabilities: capabilities)
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

    /// The three questions the find bar asks, bound to this surface's page.
    private var findPort: BrowserFindPort {
        BrowserFindPort(
            find: { query, direction in
                page.find(query, direction: direction)
            },
            matchState: { page.findMatchState },
            dismiss: page.dismissFind
        )
    }

    /// What this shell can do: a pointer rests over the chrome and nothing is
    /// aimed at with a finger.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }
}
