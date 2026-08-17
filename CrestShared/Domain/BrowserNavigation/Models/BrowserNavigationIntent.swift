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

enum BrowserNavigationResponseIntent: Equatable {
    case display
    case download

    static func classify(
        canShowMIMEType: Bool,
        response: URLResponse?
    ) -> BrowserNavigationResponseIntent {
        if !canShowMIMEType || requestsDownload(response) {
            return .download
        }
        return .display
    }

    private static func requestsDownload(_ response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse,
            let disposition = response.value(
                forHTTPHeaderField: "Content-Disposition"
            )
        else {
            return false
        }
        let directive =
            disposition
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return directive == "attachment"
    }
}

enum BrowserPopupTrigger: Equatable {
    case explicitUserNavigation
    case scripted
}
