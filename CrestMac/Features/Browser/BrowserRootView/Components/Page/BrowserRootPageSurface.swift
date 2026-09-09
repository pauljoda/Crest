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
    let space: BrowserSpace
    let isSelectedSpace: Bool
    let tabPromotionNamespace: Namespace.ID

    private var selectedTab: BrowserTab? {
        space.tabs.first { $0.id == space.selectedTabID }
    }

    private var surfacePage: BrowserPage? {
        selectedTab.flatMap { model.pages.surfacePage(for: $0, in: space, accessController: model.spaceAccess) }
    }

    private var previewsStartPage: Bool {
        !isSelectedSpace && model.pages.requiresStartPageOnEntry(to: space)
    }

    private var pageSurfacePresentation: BrowserPageSurfacePresentation {
        if previewsStartPage, !model.spaceAccess.isLocked(space) {
            let draft = space.currentTabs.first { $0.isStartPage && space.splitGroup(containing: $0.id) == nil }
            return .single(space: space, cardTabID: draft?.id)
        }
        return BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: space,
            isSelectedSpaceLocked: model.spaceAccess.isLocked(space),
            selectedTabID: space.selectedTabID,
            hasEnteredSplitContent:
                isSelectedSpace && model.browser.sidebarReorderState.hasEnteredSplitContent,
            resolvedTarget: isSelectedSpace ? model.browser.sidebarReorderState.resolvedTarget : nil,
            presentsTrailingPanel: isSelectedSpace && model.extensionSidebar?.panel != nil
        )
    }

    var body: some View {
        let presentation = pageSurfacePresentation
        return surface(presentation)
            .environment(\.spaceContentIsInteractive, isSelectedSpace)
            .allowsHitTesting(isSelectedSpace)
            .accessibilityHidden(!isSelectedSpace)
            .browserSplitContentDropZone(
                assignment: isSelectedSpace ? presentation.dropAssignment : nil,
                state: model.browser.sidebarReorderState
            )
            .environment(
                \.browserWebFocusRestorationGate,
                BrowserWebFocusRestorationGate(
                    browserChromeOwnsFocus: !isSelectedSpace || !model.isWindowFocused
                        || model.isAddressEditing || model.chrome.isCommandPalettePresented,
                    pageChromeOwnsFocus: false))
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
                isStartPage: previewsStartPage || selectedTab?.isStartPage == true,
                hasActivePage: surfacePage != nil,
                completedNavigationCount: surfacePage?.completedNavigationCount ?? 0,
                hasSelectedSpace: true,
                handleWebContentInteraction: {
                    model.chrome.utilityPresentation
                        .handleInteraction(.webContent)
                },
                content: Group {
                    if model.spaceAccess.isLocked(space) {
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
                        .background { LockedSpacePagePreview(space: space, pages: model.pages) }
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
                                model.chrome.isCommandPalettePresented,
                            previewsStartPage: previewsStartPage
                        )
                    }
                }
            )
            // The lone tab on show is a card as far as a drag is concerned: it
            // is what a dropped tab would join, and the side of it the pointer
            // is on is which side of it the new card lands.
            .browserSplitDropCardFrame(
                tabID: isSelectedSpace ? presentation.singleCardTabID : nil,
                assignment: isSelectedSpace ? presentation.dropAssignment : nil,
                state: model.browser.sidebarReorderState
            )
        }
    }
}
