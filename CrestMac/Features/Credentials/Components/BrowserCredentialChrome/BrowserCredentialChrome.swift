import SwiftUI

struct BrowserCredentialChrome: View {
    let presentation: BrowserCredentialChromePresentation
    let page: BrowserPage
    let browser: BrowserStore

    var body: some View {
        switch presentation {
        case .none:
            EmptyView()
        case .save(let candidate):
            BrowserCredentialSaveBanner(
                candidate: candidate,
                page: page,
                browser: browser
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        case .strongPassword(let request):
            BrowserStrongPasswordPanel(
                request: request,
                page: page,
                browser: browser
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

    /// What this shell can do: a pointer rests over the chrome and nothing is
    /// aimed at with a finger.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }
}
