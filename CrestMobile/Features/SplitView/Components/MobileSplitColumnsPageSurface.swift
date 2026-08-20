import SwiftUI

/// The iPadOS content area when it is laying its pages out as a row of cards.
///
/// Usually that means a group of more than one member. It also means a lone tab
/// with a drag in flight over it: the row is what a drop placeholder can open
/// beside, so `MobileRegularPageSurface` switches to it for the length of the
/// drag and this surface draws a one-card row without treating it as a special
/// case — the same thing `BrowserSplitColumnsView` does for macOS.
///
/// The regular half of `MobileRegularPageSurface`'s branch, and the iPad's use of
/// the very same `BrowserSplitColumnsView` macOS lays out — which is the point of
/// the container being shared. What the platform supplies is the card interior
/// and the two things the single detail surface attaches to its one surface: the
/// utility-fan dismissal on web-content interaction, and the per-card decision
/// about a transparent interior.
///
/// Every column is visible, so every column loads. `prepareSplitCardPages()` runs
/// on the membership change rather than per card, because there is no lazy
/// materialization here to hang it off.
struct MobileSplitColumnsPageSurface: View {
    let model: MobileBrowserRootModel
    let space: BrowserSpace
    let members: [BrowserTab]
    let adjoinsLeadingSidebar: Bool
    /// The slot a drag out of the sidebar would drop a card into.
    /// `MobileRegularPageSurface` owns the decision; the row only draws it.
    let placeholderIndex: Int?

    var body: some View {
        BrowserSplitColumnsView(
            members: members,
            focusedTabID: model.browser.selectedTab?.id,
            frameInsets: BrowserChromeLayout.pageFrameInsets(
                adjoinsLeadingSidebar: adjoinsLeadingSidebar
            ),
            accent: space.branding.primaryColor.color,
            placeholderIndex: placeholderIndex,
            // "Fancy Move" is a pointer gesture: ⇧⌘-held mouse-down, and a
            // card that follows a cursor. iPadOS reorders its cards from the
            // member menu instead, so the row here is never carrying one.
            liftedTabID: nil,
            widthTransaction: model.splitWidthTransactionBinding,
            onResizeCommit: model.commitSplitColumnFractions,
            onFocus: model.focusSplitCard,
            usesTransparentInnerSurface: usesTransparentInnerSurface,
            content: { member, _ in
                MobileSplitCardContent(
                    member: member,
                    space: space,
                    pages: model.pages,
                    viewport: .inline,
                    failureLayout: .regular,
                    handleInteraction: {
                        model.navigation.utilityPresentation
                            .handleInteraction(.webContent)
                        model.navigation.handleRegularPageInteraction()
                    },
                    requestFocus: { model.focusSplitCard(member.id) }
                )
                // Where this card sits, in the space a drag resolves in, so a
                // tab dropped on the row lands in the slot the finger is
                // actually over. The Space rides along because the registry
                // outlives the presentation that filled it.
                .browserSplitDropCardFrame(
                    tabID: member.id,
                    assignment: BrowserSpaceRuntimeAssignment(space: space),
                    state: model.browser.sidebarReorderState
                )
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                model.navigation.utilityPresentation.handleInteraction(.webContent)
                model.navigation.handleRegularPageInteraction()
            }
        )
        .onChange(of: members.map(\.id), initial: true) { _, _ in
            model.seedSplitColumnFractions()
            model.prepareSplitCardPages()
        }
    }

    /// The transparent-interior decision, made per card rather than once for the
    /// window: a start-page card shows the Space's atmosphere through it while its
    /// loaded neighbours keep their opaque page background.
    private func usesTransparentInnerSurface(_ member: BrowserTab) -> Bool {
        BrowserPageSurfacePolicy.usesTransparentInnerSurface(
            isStartPage: member.isStartPage,
            hasActivePage: model.pages.residentPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: member.id,
                    spaceID: space.id,
                    profileID: space.profile.id
                )
            ) != nil
        )
    }
}
