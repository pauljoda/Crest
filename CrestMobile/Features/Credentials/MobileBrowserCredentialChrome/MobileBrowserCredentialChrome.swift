import SwiftUI

struct MobileBrowserCredentialChrome: View {
    let page: MobileBrowserPage
    let browser: BrowserStore

    var body: some View {
        switch presentation {
        case .none:
            EmptyView()
        case .save(let candidate):
            MobileCredentialSavePrompt(candidate: candidate, page: page, browser: browser)
                .transition(.move(edge: .top).combined(with: .opacity))
        case .strongPassword(let request):
            MobileStrongPasswordPrompt(
                request: request,
                page: page,
                browser: browser,
                capabilities: capabilities
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        case .suggestions(let request):
            BrowserCredentialSuggestionPrompt(
                request: request,
                port: fillPort,
                browser: browser,
                capabilities: capabilities
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var presentation: BrowserCredentialChromePresentation {
        BrowserCredentialChromePresentation.resolve(
            saveCandidate: page.credentialSaveCandidate,
            fillRequest: page.credentialFillRequest
        )
    }

    /// The four things a fill prompt asks, bound to this chrome's page.
    private var fillPort: BrowserCredentialFillPort {
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

    /// What this shell can do, as far as the credential prompts are concerned:
    /// every row is aimed at with a finger.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities(supportsTouch: true)
    }
}
