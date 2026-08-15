import SwiftUI

struct MobileBrowserCredentialChrome: View {
    let page: MobileBrowserPage
    let browser: BrowserStore

    var body: some View {
        if let candidate = page.credentialSaveCandidate {
            MobileCredentialSavePrompt(candidate: candidate, page: page, browser: browser)
                .transition(.move(edge: .top).combined(with: .opacity))
        } else if let request = page.credentialFillRequest {
            if request.passwordKind == .new {
                MobileStrongPasswordPrompt(request: request, page: page, browser: browser)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                MobileCredentialSuggestionPrompt(request: request, page: page, browser: browser)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

#Preview("Credential Chrome — Idle") {
    let fixture = MobileBrowserCredentialChromePreviewFixture()

    MobileBrowserCredentialChrome(
        page: fixture.page,
        browser: fixture.browser
    )
    .frame(width: 390)
}
