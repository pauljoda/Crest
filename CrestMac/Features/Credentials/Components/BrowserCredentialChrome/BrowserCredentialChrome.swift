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
