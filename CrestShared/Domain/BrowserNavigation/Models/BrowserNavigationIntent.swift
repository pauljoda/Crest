import Foundation

enum BrowserNavigationIntent: Equatable {
    case allow
    case openInNewTab(URL)
    case download
    /// Another application owns this URL. The page cancels and hands it over.
    case handOffToSystem(URL)
    /// Nothing may load this URL and nothing may open it.
    case blockScheme

    static func classify(
        url: URL?,
        hasTargetFrame: Bool,
        shouldPerformDownload: Bool,
        isAppInitiated: Bool = false
    ) -> BrowserNavigationIntent {
        // The scheme is settled first: a `mailto:` link with `target="_blank"`
        // belongs to the mail client, not to a new Crest tab, and a scheme Crest
        // refuses must not become a download either.
        switch BrowserExternalSchemePolicy.disposition(
            for: url,
            isAppInitiated: isAppInitiated
        ) {
        case .webKit:
            break
        case .blocked:
            return .blockScheme
        case .handOff:
            if let url {
                return .handOffToSystem(url)
            }
        }
        if shouldPerformDownload {
            return .download
        }
        if !hasTargetFrame, let url {
            return .openInNewTab(url)
        }
        return .allow
    }
}
