import SwiftUI

struct BrowserExternalLinkHandler: ViewModifier {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let spaceAccess: BrowserSpaceAccessController
    let targetWindowID: BrowserWindowID

    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .handlesExternalEvents(
                preferring:
                    BrowserExternalLinkScenePolicy.existingBrowserPreference,
                allowing:
                    BrowserExternalLinkScenePolicy.existingBrowserPreference
            )
            .onOpenURL { url in
                Task { await open(url) }
            }
    }

    private func open(_ url: URL) async {
        // A document opened from Finder, Open With, or `open -a Crest` has no host
        // for the link-preference rules to route on, and it is not a web link. It
        // belongs in the Space already on screen.
        if url.isFileURL {
            guard BrowserCorePolicy.acceptsLocalDocument(url),
                let spaceID = browser.selectedSpace?.id,
                let assignment = await accessibleAssignment(for: spaceID)
            else { return }
            actions.openLocalDocuments([url], in: assignment)
            return
        }
        guard BrowserCorePolicy.acceptsExternalURL(url) else { return }
        let decision = BrowserLinkPreferenceStore.shared.routingDecision(
            for: url,
            in: browser.session,
            unavailableSpaceIDs: browser.deletingSpaceIDs
        )
        // A locked routed Space never raises a prompt for a link that arrived
        // from another process; the link lands in a Quick Window instead.
        guard
            let destination = BrowserExternalLinkLockPolicy.destination(
                routedTo: decision.spaceID,
                selectedSpaceID: browser.selectedSpace?.id,
                spaces: browser.session.spaces,
                unavailableSpaceIDs: browser.deletingSpaceIDs,
                isLocked: spaceAccess.isLocked
            ),
            let assignment = await accessibleAssignment(
                for: destination.space.id
            )
        else { return }
        let effective: BrowserLinkRoutingDecision =
            destination.substitutesForLockedSpace
            ? .quickWindow(spaceID: destination.space.id) : decision
        switch effective {
        case .quickWindow:
            openWindow(
                id: BrowserSceneID.quickWindow.rawValue,
                value: BrowserQuickWindowRequest(
                    url: url,
                    spaceAssignment: assignment,
                    targetWindowID: targetWindowID
                )
            )
        case .space:
            guard
                browser.openNewTab(
                    url: url,
                    matching: assignment
                ) != nil
            else { return }
            pages.select(session: browser.session)
            pages.load(url)
            chrome.dismissCommandPalette()
        }
    }

    /// One implementation of local-document opening, shared with the File menu's
    /// Open File… rather than copied here.
    private var actions: BrowserCommandActions {
        BrowserCommandActions(
            browser: browser,
            pages: pages,
            chrome: chrome,
            openWindow: openWindow,
            spaceAccess: spaceAccess,
            targetWindowID: targetWindowID
        )
    }

    private func accessibleAssignment(
        for spaceID: SpaceID
    ) async -> BrowserSpaceRuntimeAssignment? {
        guard let space = browser.session.space(id: spaceID) else { return nil }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard await spaceAccess.unlock(space),
            browser.space(matching: assignment) != nil
        else { return nil }
        return assignment
    }
}
