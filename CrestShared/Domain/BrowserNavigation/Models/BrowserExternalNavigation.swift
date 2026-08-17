import Foundation

/// Which engine, if any, owns a navigation once its URL scheme is known.
enum BrowserExternalSchemeDisposition: Equatable, Sendable {
    /// WebKit's to load — or to refuse on its own terms.
    case webKit
    /// Neither WebKit nor another app may see it.
    case blocked
    /// Another application owns the scheme. Crest cancels and hands it to the OS.
    case handOff
}

/// The answer to one external-app prompt. Cancelling is deliberately not a
/// remembered block: a person declining one hand-off has not asked Crest to
/// refuse every future one, which Site Permissions is there for.
enum BrowserExternalSchemePromptResponse: Equatable, Sendable {
    case open
    case openAndRemember
    case cancel
}

enum BrowserModifiedLinkDisposition: Equatable, Sendable {
    case navigate
    case backgroundTab(URL)
    case foregroundTab(URL)

    static func classify(
        destinationURL: URL?,
        isUserActivatedLink: Bool,
        isCommandModified: Bool,
        isShiftModified: Bool,
        isMiddleClick: Bool
    ) -> BrowserModifiedLinkDisposition {
        guard isUserActivatedLink,
            isCommandModified || isMiddleClick,
            let destinationURL,
            BrowserExternalURLPolicy.accepts(destinationURL)
        else {
            return .navigate
        }
        return isShiftModified
            ? .foregroundTab(destinationURL)
            : .backgroundTab(destinationURL)
    }
}
