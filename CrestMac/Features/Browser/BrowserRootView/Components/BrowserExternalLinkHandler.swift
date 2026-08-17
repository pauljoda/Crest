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
        guard BrowserExternalURLPolicy.accepts(url) else { return }
        let decision = BrowserLinkPreferenceStore.shared.routingDecision(
            for: url,
            in: browser.session,
            unavailableSpaceIDs: browser.deletingSpaceIDs
        )
        guard
            let assignment = await accessibleAssignment(
                for: decision.spaceID
            )
        else { return }
        switch decision {
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
