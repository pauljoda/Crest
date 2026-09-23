import AppKit

/// Link destinations for an engine that runs its own link menu and
/// modified-click handling. They run the same shared commands the WebKit menu
/// and navigation delegate use.
extension BrowserPage {
    /// Opens `url` as a new card beside the tab this page presents.
    func openLinkInSplitView(_ url: URL) {
        guard let context = navigationContext,
            BrowserCorePolicy.acceptsExternalURL(url)
        else { return }
        splitLinkHost.openLink(url, context.tabID, context.assignment)
    }

    func performEngineLinkAction(_ action: BrowserEngineLinkAction, destination: URL, label: String) -> Bool {
        guard let context = navigationContext else { return false }
        switch action {
        // A selection search carries its text as the label; it goes where the
        // WebKit menu's does, with the Space's own search provider.
        case .canSearch, .search:
            let source = BrowserTabRuntimeAssignment(
                tabID: context.tabID, spaceID: context.spaceID, profileID: context.assignment.profileID)
            guard let search = linkDestinationHost.selectionSearch(for: label, from: source) else { return false }
            guard action == .search else { return true }
            return linkDestinationHost.openLink(
                search.url, from: search.source,
                in: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID))
        default: break
        }
        guard BrowserCorePolicy.acceptsExternalURL(destination) else { return false }
        switch action {
        case .canPeek: return true
        case .peek:
            openPeek(
                BrowserPeekRequest(
                    url: destination, sourceTabID: context.tabID,
                    sourceTitle: context.title, spaceAssignment: context.assignment,
                    trigger: .contextMenu))
            return true
        // The engine asks while AppKit holds the main thread building the
        // menu, so availability answers from store state.
        case .canSplit: return splitLinkHost.canOpenLink(context.tabID, context.assignment)
        case .split:
            openLinkInSplitView(destination)
            return true
        case .drag: return linkDrag?.beginNativeLink(url: destination, label: label) == true
        case .canSearch, .search: return false
        }
    }

    /// The Peek a protected link opens instead of navigating, or nil to let
    /// the engine navigate. The engine cancels first and runs the action once
    /// it has left its navigation stack.
    func protectedLinkAction(to destination: URL) -> (() -> Void)? {
        guard let context = navigationContext,
            let sourceWindow = nativeView.window,
            let request = BrowserPeekPolicy.request(
                destinationURL: destination, context: context,
                isUserActivatedLink: true, isTopLevelNavigation: true, isAlternateModified: false)
        else { return nil }
        // A moved or reassigned source must not open Peek.
        return { [weak self, weak sourceWindow] in
            guard let self, let sourceWindow, self.nativeView.window === sourceWindow,
                let current = self.navigationContext,
                current.tabID == context.tabID, current.assignment == context.assignment,
                current.placement == context.placement, current.savedURL == context.savedURL,
                current.automaticallyOpensPeek
            else { return }
            self.openPeek(request)
        }
    }

    /// Classifies a modified link click the engine intercepted. A Peek comes
    /// with the action that opens it; `discard` releases the engine's staged
    /// navigation when the source moved before the action ran.
    func modifiedLinkDecision(
        to destination: URL,
        modifiers: BrowserEngineLinkModifiers,
        navigationToken token: String,
        discard: @escaping @MainActor () -> Void
    ) -> (BrowserLinkNavigationDecision, (() -> Void)?) {
        let preferences = BrowserLinkPreferenceStore.shared.preferences
        let decision = BrowserLinkNavigationDecision.classifyModifiedLink(
            destinationURL: destination, context: navigationContext,
            isUserActivatedLink: true, isTopLevelNavigation: true,
            isCommandModified: modifiers.contains(.command), isOptionModified: modifiers.contains(.option),
            isMiddleClick: modifiers.contains(.middleClick), peekModifier: preferences.peekClickModifier,
            isShiftModified: modifiers.contains(.shift),
            focusesNewTabs: opensModifiedLinksInForeground || preferences.focusesNewTabsOpenedFromLinks)
        guard decision == .peekModifier else { return (decision, nil) }
        guard let context = navigationContext, let sourceWindow = nativeView.window,
            let request = decision.peekRequest(
                destinationURL: destination, context: context,
                engineNavigation: BrowserEngineNavigation(
                    implementation: pageEngine.registration.implementationId, token: token))
        else { return (.navigate, nil) }
        return (
            decision,
            { [weak self, weak sourceWindow] in
                guard let self, let sourceWindow, self.nativeView.window === sourceWindow,
                    let current = self.navigationContext,
                    current.tabID == context.tabID, current.assignment == context.assignment
                else {
                    discard()
                    return
                }
                self.openPeek(request)
            }
        )
    }
}
