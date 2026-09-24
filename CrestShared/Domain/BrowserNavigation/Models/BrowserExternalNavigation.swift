import Foundation

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
        isMiddleClick: Bool,
        focusesNewTabs: Bool = false
    ) -> BrowserModifiedLinkDisposition {
        guard let destinationURL else { return .navigate }
        let decision = LinkNavigationDecision.classify(destinationURL: destinationURL, context: nil,
            isUserActivatedLink: isUserActivatedLink, isTopLevelNavigation: true,
            isPeekModified: false, isNewTabModified: isCommandModified || isMiddleClick,
            isShiftModified: isShiftModified, focusesNewTabs: focusesNewTabs)
        guard decision.opensTab else { return .navigate }
        return decision.selectsTab ? .foregroundTab(destinationURL) : .backgroundTab(destinationURL)
    }
}

/// Selection is independent of how WebKit loads the destination. An ordinary
/// new-window request retains its foreground behavior; Shift reverses the
/// stored choice only when WebKit reports a new-tab gesture.
enum BrowserLinkOpeningPolicy {
    static func selectsNewTab(
        isNewTabGesture: Bool,
        isShiftModified: Bool,
        focusesNewTabs: Bool
    ) -> Bool {
        guard isNewTabGesture else { return true }
        return focusesNewTabs != isShiftModified
    }
}
