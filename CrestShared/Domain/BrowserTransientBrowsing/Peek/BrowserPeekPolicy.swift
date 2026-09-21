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
enum BrowserLinkNavigationDecision: String {
    case navigate, peekModifier, peekSavedSite, backgroundTab, foregroundTab

    static func classifyModifiedLink(destinationURL: URL?, context: BrowserPageNavigationContext?,
        isUserActivatedLink: Bool, isTopLevelNavigation: Bool, isCommandModified: Bool,
        isOptionModified: Bool, isMiddleClick: Bool, peekModifier: BrowserLinkClickModifier,
        isShiftModified: Bool, focusesNewTabs: Bool) -> Self {
        #if CREST_CORE_BACKED
        return BrowserCorePolicy.modifiedLinkNavigation(destinationURL: destinationURL, context: context,
            isUserActivatedLink: isUserActivatedLink, isTopLevelNavigation: isTopLevelNavigation,
            isCommandModified: isCommandModified, isOptionModified: isOptionModified,
            isMiddleClick: isMiddleClick, peekModifier: peekModifier,
            isShiftModified: isShiftModified, focusesNewTabs: focusesNewTabs)
        #else
        let intent = BrowserLinkClickModifierPolicy.intent(isCommandModified: isCommandModified,
            isOptionModified: isOptionModified, peekModifier: peekModifier)
        return classify(destinationURL: destinationURL, context: context,
            isUserActivatedLink: isUserActivatedLink, isTopLevelNavigation: isTopLevelNavigation,
            isPeekModified: intent == .peek, isNewTabModified: intent == .newTab || isMiddleClick,
            isShiftModified: isShiftModified, focusesNewTabs: focusesNewTabs)
        #endif
    }

    static func classify(destinationURL: URL?, context: BrowserPageNavigationContext?,
        isUserActivatedLink: Bool, isTopLevelNavigation: Bool,
        isPeekModified: Bool, isNewTabModified: Bool, isShiftModified: Bool = false,
        focusesNewTabs: Bool = false) -> Self {
        #if CREST_CORE_BACKED
        return BrowserCorePolicy.linkNavigation(destinationURL: destinationURL, context: context,
            isUserActivatedLink: isUserActivatedLink, isTopLevelNavigation: isTopLevelNavigation,
            isPeekModified: isPeekModified, isNewTabModified: isNewTabModified,
            isShiftModified: isShiftModified, focusesNewTabs: focusesNewTabs)
        #else
        guard isUserActivatedLink, let destinationURL,
            BrowserExternalURLPolicy.accepts(destinationURL) else { return .navigate }
        if isTopLevelNavigation, context != nil, isPeekModified { return .peekModifier }
        if isNewTabModified { return focusesNewTabs != isShiftModified ? .foregroundTab : .backgroundTab }
        if isTopLevelNavigation, let context, context.automaticallyOpensPeek,
            context.placement == .pinned || context.placement == .saved,
            let savedURL = context.savedURL, !BrowserSavedSitePolicy.isSameSite(savedURL, destinationURL) {
            return .peekSavedSite
        }
        return .navigate
        #endif
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
