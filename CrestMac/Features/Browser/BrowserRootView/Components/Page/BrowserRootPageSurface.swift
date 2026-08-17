import SwiftUI

struct BrowserRootPageSurface: View {
    let model: BrowserRootModel
    let tabPromotionNamespace: Namespace.ID

    private var hasActivePage: Bool {
        model.browser.selectedTab.map {
            model.pages.activeTabID == $0.id && model.pages.activePage != nil
        } ?? false
    }

    private var usesTransparentInnerSurface: Bool {
        BrowserPageSurfacePolicy.usesTransparentInnerSurface(
            isStartPage: model.browser.selectedTab?.isStartPage == true,
            hasActivePage: hasActivePage
        )
    }

    /// The Space whose cards this window is showing, or `nil` when there are
    /// none to show. A locked Space presents its access gate instead of pages,
    /// so it counts as none: the page pool has already dropped every card, and
    /// nothing may be dropped into a Space that has not been unlocked.
    private var presentingSpace: BrowserSpace? {
        guard let space = model.browser.selectedSpace,
            !model.spaceAccess.isLocked(space)
        else { return nil }
        return space
    }

    /// The slot a drag in flight would drop a card into, for this Space.
    private var splitInsertIndex: Int? {
        guard let space = presentingSpace,
            case .splitInsert(let assignment, let index) =
                model.browser.sidebarReorderState.resolvedTarget?.kind,
            assignment.spaceID == space.id
        else { return nil }
        return index
    }

    /// The cards to lay out as columns, or `nil` for the single-surface path.
    ///
    /// Two things open the columns layout. A group of more than one member is
    /// the obvious one. The other is a drag that has reached the content area:
    /// a window presenting a single tab has to become a one-card row before it
    /// can show a drop placeholder beside that tab, and it stays one for the
    /// rest of the drag rather than following the pointer back and forth —
    /// every flip between the two layouts hands the live web view to a
    /// different host, and the placeholder coming and going inside the columns
    /// layout is only a width change.
    private var splitMembers: [BrowserTab]? {
        guard presentingSpace != nil else { return nil }
        let members = model.presentedSplitMembers
        guard !members.isEmpty,
            members.count > 1 || isColumnsLayoutHeldOpenByDrag
        else { return nil }
        return members
    }

    /// Whether a drag that has already reached the content area is keeping the
    /// columns layout open around a single presented tab.
    private var isColumnsLayoutHeldOpenByDrag: Bool {
        model.browser.sidebarReorderState.hasEnteredSplitContent
    }

    var body: some View {
        surface
            .browserSplitContentDropZone(
                assignment: presentingSpace.map(
                    BrowserSpaceRuntimeAssignment.init(space:)
                ),
                state: model.browser.sidebarReorderState
            )
    }

    @ViewBuilder
    private var surface: some View {
        if let space = presentingSpace, let members = splitMembers {
            BrowserSplitPageSurface(
                model: model,
                space: space,
                members: members,
                placeholderIndex: splitInsertIndex,
                tabPromotionNamespace: tabPromotionNamespace
            )
        } else {
            BrowserRootContentSurface(
                cornerRadius: BrowserChromeLayout.pageCornerRadius,
                seamWidth: BrowserChromeLayout.pageBrandSeamWidth,
                frameInsets: BrowserChromeLayout.pageFrameInsets(
                    adjoinsLeadingSidebar:
                        model.sidebarPresentation.reservesSidebarWidth
                ),
                usesTransparentInnerSurface: usesTransparentInnerSurface,
                showsFallbackBorder: model.browser.selectedSpace == nil
            ) {
                Group {
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
                            browser: model.browser,
                            pages: model.pages,
                            spaceAccess: model.spaceAccess,
                            tabPromotionNamespace: tabPromotionNamespace,
                            isCommandPalettePresented:
                                model.chrome.isCommandPalettePresented
                        )
                    }
                }
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    model.chrome.utilityPresentation.handleInteraction(.webContent)
                }
            )
            // The lone tab on show is a card as far as a drag is concerned: it
            // is what a dropped tab would join, and the side of it the pointer
            // is on is which side of it the new card lands.
            .browserSplitDropCardFrame(
                tabID: singleCardTabID,
                state: model.browser.sidebarReorderState
            )
        }
    }

    /// The tab the single surface is showing, when there is one to drop beside.
    private var singleCardTabID: TabID? {
        guard presentingSpace != nil else { return nil }
        return model.browser.selectedTab?.id
    }
}
