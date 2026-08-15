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
            BrowserCredentialSuggestionPanel(
                request: request,
                page: page,
                browser: browser
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview("Credential Chrome — Strong Password") {
    let preview = BrowserCredentialChromePreviewFixture.makeWebContent()

    BrowserCredentialChrome(
        presentation: .strongPassword(
            BrowserCredentialChromePreviewFixture.newCredentialRequest
        ),
        page: preview.page,
        browser: preview.browser
    )
    .padding()
    .frame(width: 460, height: 360, alignment: .top)
}
