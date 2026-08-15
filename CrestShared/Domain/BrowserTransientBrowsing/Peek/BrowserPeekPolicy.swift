import Foundation

enum BrowserPeekPolicy {
    static func longPressRequest(
        destinationURL: URL?,
        context: BrowserPageNavigationContext?,
        sourcePresentation: BrowserPeekSourcePresentation? = nil
    ) -> BrowserPeekRequest? {
        guard let destinationURL,
            BrowserExternalURLPolicy.accepts(destinationURL),
            let context
        else { return nil }

        return BrowserPeekRequest(
            url: destinationURL,
            sourceTabID: context.tabID,
            sourceTitle: context.title,
            spaceAssignment: context.assignment,
            trigger: .longPress,
            sourcePresentation: sourcePresentation
        )
    }

    static func request(
        destinationURL: URL?,
        context: BrowserPageNavigationContext?,
        isUserActivatedLink: Bool,
        isTopLevelNavigation: Bool,
        isAlternateModified: Bool,
        isNewTabModified: Bool = false,
        sourcePresentation: BrowserPeekSourcePresentation? = nil
    ) -> BrowserPeekRequest? {
        guard isUserActivatedLink,
            isTopLevelNavigation,
            let destinationURL,
            BrowserExternalURLPolicy.accepts(destinationURL),
            let context
        else { return nil }

        if isAlternateModified {
            return BrowserPeekRequest(
                url: destinationURL,
                sourceTabID: context.tabID,
                sourceTitle: context.title,
                spaceAssignment: context.assignment,
                trigger: .modifierClick,
                sourcePresentation: sourcePresentation
            )
        }

        guard !isNewTabModified else { return nil }

        guard context.automaticallyOpensPeek,
            context.placement == .pinned || context.placement == .saved,
            let savedURL = context.savedURL,
            !BrowserSavedSitePolicy.isSameSite(savedURL, destinationURL)
        else {
            return nil
        }

        return BrowserPeekRequest(
            url: destinationURL,
            sourceTabID: context.tabID,
            sourceTitle: context.title,
            spaceAssignment: context.assignment,
            trigger: .protectedSavedSite,
            sourcePresentation: sourcePresentation
        )
    }
}
