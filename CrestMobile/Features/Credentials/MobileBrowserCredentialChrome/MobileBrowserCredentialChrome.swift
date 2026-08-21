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
            MobileStrongPasswordPrompt(request: request, page: page, browser: browser)
                .transition(.move(edge: .top).combined(with: .opacity))
        case .suggestions(let request):
            MobileCredentialSuggestionPrompt(request: request, page: page, browser: browser)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var presentation: BrowserCredentialChromePresentation {
        BrowserCredentialChromePresentation.resolve(
            saveCandidate: page.credentialSaveCandidate,
            fillRequest: page.credentialFillRequest
        )
    }
}
