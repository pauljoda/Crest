#if DEBUG
    import SwiftUI

    /// The sidebar's preview Space as a tab's or folder's card draws it: its
    /// read model in a memory-only store, and a list context whose actions
    /// answer without touching a page.
    @MainActor
    enum BrowserTabPreviewFixture {
        // MARK: - Static Variables

        static let browser = BrowserSidebarPreviewFixture.makeBrowser()
        static let sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        private static let spaceAccess = BrowserSidebarPreviewFixture.makeSpaceAccess()

        // MARK: - Actions - Fixtures

        /// The Space's list as its sidebar draws it.
        static var context: BrowserSidebarListContext? {
            guard let space = browser.workspaceModel?.spaces.models.first, let window = browser.windowModel else {
                return nil
            }
            return BrowserSidebarListContext(
                space: space, window: window, favicons: browser.core.state.favicons, browser: browser,
                spaceAccess: spaceAccess, pageAccess: BrowserSidebarPreviewFixture.makePageAccess(),
                tabActions: BrowserSidebarTabActions(
                    assignment: BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID),
                    browser: browser, reorderState: sidebarInteraction.sidebarReorderState, spaceAccess: spaceAccess,
                    syncPagesAfterMutation: {}, pullFavicon: { _, _ in nil }),
                capabilities: BrowserInteractionCapabilities(), select: { _ in })
        }

        /// The Space's folder.
        static var folder: FolderStateModel? {
            context?.space.folders.models.first
        }

        /// A tab the Space holds outside its folder.
        static var tab: TabStateModel? {
            context?.space.tabs.models.first { $0.folderID == nil && $0.placement == .current }
        }

        /// A stand-in for the picture Crest takes of a page.
        static let picture = BrowserTabPreviewPicture(
            image: Image(systemName: "rectangle.on.rectangle.angled"), aspectRatio: 0.6)
    }
#endif
