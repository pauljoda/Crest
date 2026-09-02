import SwiftUI

/// The macOS content area, and the one place that decides between real columns
/// and the single rounded page surface.
///
/// The branch is `BrowserPageSurfaceBranchPolicy`'s rather than this view's, so
/// iPadOS opens and closes its columns on exactly the same conditions. What is
/// left here is macOS's half: which surface draws the answer, and what the
/// pointer may do to it.
struct BrowserRootPageSurface: View {
    let model: BrowserRootModel
    let tabPromotionNamespace: Namespace.ID

    private var hasActivePage: Bool {
        model.browser.selectedTab.map {
            model.pages.activeTabID == $0.id && model.pages.activePage != nil
        } ?? false
    }

    private var completedNavigationCount: Int {
        guard hasActivePage else { return 0 }
        return model.pages.activePage?.completedNavigationCount ?? 0
    }

    private var pageSurfacePresentation: BrowserPageSurfacePresentation {
        let selectedSpace = model.browser.selectedSpace
        return BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: selectedSpace,
            isSelectedSpaceLocked: selectedSpace.map {
                model.spaceAccess.isLocked($0)
            } ?? false,
            selectedTabID: model.browser.selectedTab?.id,
            hasEnteredSplitContent:
                model.browser.sidebarReorderState.hasEnteredSplitContent,
            resolvedTarget: model.browser.sidebarReorderState.resolvedTarget
        )
    }

    var body: some View {
        let presentation = pageSurfacePresentation
        return surface(presentation)
            .browserSplitContentDropZone(
                assignment: presentation.dropAssignment,
                state: model.browser.sidebarReorderState
            )
    }

    @ViewBuilder
    private func surface(
        _ presentation: BrowserPageSurfacePresentation
    ) -> some View {
        if case .columns(let space, let members, let placeholderIndex) =
            presentation
        {
            BrowserSplitPageSurface(
                model: model,
                space: space,
                members: members,
                placeholderIndex: placeholderIndex,
                tabPromotionNamespace: tabPromotionNamespace
            )
        } else {
            BrowserRootDetailSurface(
                adjoinsLeadingSidebar:
                    model.sidebarPresentation.reservesSidebarWidth,
                usesBorderlessFrame: false,
                isStartPage: model.browser.selectedTab?.isStartPage == true,
                hasActivePage: hasActivePage,
                completedNavigationCount: completedNavigationCount,
                hasSelectedSpace: model.browser.selectedSpace != nil,
                handleWebContentInteraction: {
                    model.chrome.utilityPresentation
                        .handleInteraction(.webContent)
                },
                content: Group {
                    if let space = model.browser.selectedSpace,
                        model.spaceAccess.isLocked(space)
                    {
                        BrowserSpaceAccessView(
                            space: space,
                            spaces: model.browser.session.spaces,
                            accessController: model.spaceAccess,
                            selectSpace: { assignment in
                                guard
                                    let candidate = model.browser.space(
                                        matching: assignment
                                    ), !model.spaceAccess.isLocked(candidate)
                                else { return }
                                model.browser.selectSpace(assignment.spaceID)
                            },
                            presentation: .contentOverlay
                        )
                    } else {
                        BrowserDetailView(
                            presentation: presentation,
                            browser: model.browser,
                            pages: model.pages,
                            spaceAccess: model.spaceAccess,
                            tabPromotionNamespace: tabPromotionNamespace,
                            startPageFocusRequest:
                                model.chrome.startPageFocusRequest,
                            isCommandPalettePresented:
                                model.chrome.isCommandPalettePresented
                        )
                    }
                }
            )
            // The lone tab on show is a card as far as a drag is concerned: it
            // is what a dropped tab would join, and the side of it the pointer
            // is on is which side of it the new card lands.
            .browserSplitDropCardFrame(
                tabID: presentation.singleCardTabID,
                assignment: presentation.dropAssignment,
                state: model.browser.sidebarReorderState
            )
        }
    }
}
