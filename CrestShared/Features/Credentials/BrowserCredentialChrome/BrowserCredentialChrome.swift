import SwiftUI

/// The credential prompt a page is presenting, on every shell.
///
/// Which prompt that is comes from `BrowserCredentialChromePresentation`, what
/// each prompt can do to the page comes from the two ports, and how each one is
/// drawn comes from what the shell says it can do. Nothing about the chrome is
/// left for a shell to decide twice.
struct BrowserCredentialChrome: View {
    let presentation: BrowserCredentialChromePresentation
    let fillPort: BrowserCredentialFillPort
    let savePort: BrowserCredentialSavePort
    let browser: BrowserStore
    let capabilities: BrowserInteractionCapabilities

    var body: some View {
        switch presentation {
        case .none:
            EmptyView()
        case .save(let candidate):
            BrowserCredentialSavePrompt(
                candidate: candidate,
                port: savePort,
                browser: browser,
                capabilities: capabilities
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        case .strongPassword(let request):
            BrowserStrongPasswordPrompt(
                request: request,
                port: fillPort,
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
}
