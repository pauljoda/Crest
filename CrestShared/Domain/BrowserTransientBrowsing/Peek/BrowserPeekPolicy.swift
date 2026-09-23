import Foundation

enum BrowserPeekPolicy {
    static func request(
        destinationURL: URL?,
        context: BrowserPageNavigationContext?,
        isUserActivatedLink: Bool,
        isTopLevelNavigation: Bool,
        isAlternateModified: Bool,
        isNewTabModified: Bool = false,
        sourcePresentation: BrowserPeekSourcePresentation? = nil
    ) -> BrowserPeekRequest? {
        let decision = BrowserLinkNavigationDecision.classify(
            destinationURL: destinationURL, context: context,
            isUserActivatedLink: isUserActivatedLink, isTopLevelNavigation: isTopLevelNavigation,
            isPeekModified: isAlternateModified, isNewTabModified: isNewTabModified)
        return decision.peekRequest(destinationURL: destinationURL, context: context,
            sourcePresentation: sourcePresentation)
    }
}

/// Engine-neutral policy result. Native views only construct the presentation
/// after the core has selected the destination's browsing behavior.
enum BrowserLinkNavigationDecision: String, Decodable {
    case navigate, peekModifier, peekSavedSite, backgroundTab, foregroundTab

    static func classifyModifiedLink(destinationURL: URL?, context: BrowserPageNavigationContext?,
        isUserActivatedLink: Bool, isTopLevelNavigation: Bool, isCommandModified: Bool,
        isOptionModified: Bool, isMiddleClick: Bool, peekModifier: BrowserLinkClickModifier,
        isShiftModified: Bool, focusesNewTabs: Bool) -> Self {
        return BrowserCorePolicy.modifiedLinkNavigation(destinationURL: destinationURL, context: context,
            isUserActivatedLink: isUserActivatedLink, isTopLevelNavigation: isTopLevelNavigation,
            isCommandModified: isCommandModified, isOptionModified: isOptionModified,
            isMiddleClick: isMiddleClick, peekModifier: peekModifier,
            isShiftModified: isShiftModified, focusesNewTabs: focusesNewTabs)
    }

    static func classify(destinationURL: URL?, context: BrowserPageNavigationContext?,
        isUserActivatedLink: Bool, isTopLevelNavigation: Bool,
        isPeekModified: Bool, isNewTabModified: Bool, isShiftModified: Bool = false,
        focusesNewTabs: Bool = false) -> Self {
        return BrowserCorePolicy.linkNavigation(destinationURL: destinationURL, context: context,
            isUserActivatedLink: isUserActivatedLink, isTopLevelNavigation: isTopLevelNavigation,
            isPeekModified: isPeekModified, isNewTabModified: isNewTabModified,
            isShiftModified: isShiftModified, focusesNewTabs: focusesNewTabs)
    }

    func peekRequest(destinationURL: URL?, context: BrowserPageNavigationContext?,
        sourcePresentation: BrowserPeekSourcePresentation? = nil,
        engineNavigation: BrowserEngineNavigation? = nil) -> BrowserPeekRequest? {
        guard self == .peekModifier || self == .peekSavedSite,
            let destinationURL, let context else { return nil }
        return BrowserPeekRequest(url: destinationURL, sourceTabID: context.tabID,
            sourceTitle: context.title, spaceAssignment: context.assignment,
            trigger: self == .peekModifier ? .modifierClick : .protectedSavedSite,
            sourcePresentation: sourcePresentation, engineNavigation: engineNavigation)
    }
}
