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
                fillPort: credentialFillPort,
                savePort: credentialSavePort,
                browser: browser,
                capabilities: capabilities
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

    /// The four questions the find bar asks, bound to this surface's page.
    private var findPort: BrowserFindPort {
        BrowserFindPort(
            find: { query, direction in
                page.find(query, direction: direction)
            },
            matchState: { page.findMatchState },
            focusRequest: { page.findFocusRequest },
            dismiss: page.dismissFind
        )
    }

    /// The four things a credential fill prompt asks, bound to this surface's
    /// page.
    private var credentialFillPort: BrowserCredentialFillPort {
        BrowserCredentialFillPort(
            spaceID: page.spaceID,
            fill: { credential, requestID in
                try await page.fillCredential(credential, for: requestID)
            },
            fillGeneratedPassword: { password, requestID in
                try await page.fillGeneratedPassword(password, for: requestID)
            },
            dismiss: page.dismissCredentialFillRequest
        )
    }

    /// What the save prompt asks of this surface's page. This shell makes no
    /// offer to the system's Passwords app, so it binds none.
    private var credentialSavePort: BrowserCredentialSavePort {
        BrowserCredentialSavePort(
            spaceID: page.spaceID,
            presentedCandidateID: { page.credentialSaveCandidate?.id },
            dismiss: page.dismissCredentialSaveCandidate,
            offerToSystemPasswords: nil
        )
    }

    /// What this shell can do: a pointer rests over the chrome and nothing is
    /// aimed at with a finger.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }
}
