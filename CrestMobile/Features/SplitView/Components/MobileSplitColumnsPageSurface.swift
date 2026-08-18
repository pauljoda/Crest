import SwiftUI

/// The iPadOS content area when it is presenting more than one card.
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

    var body: some View {
        BrowserSplitColumnsView(
            members: members,
            focusedTabID: model.browser.selectedTab?.id,
            frameInsets: BrowserChromeLayout.pageFrameInsets(
                adjoinsLeadingSidebar: adjoinsLeadingSidebar
            ),
            accent: space.branding.primaryColor.color,
            placeholderIndex: nil,
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
