import SwiftUI

/// One cell of the iPhone carousel.
///
/// The cell owns one thing the shared card interior does not: asking the store
/// for this member's page as the cell materializes. That request is what keeps a
/// four-member group to focused ±1 live web views — `LazyHStack` builds the
/// neighbours and nothing further, so nothing further is ever built.
///
/// The viewport arrives from `MobileBrowserDetailView` rather than being
/// resolved here. It is the same value the selected tab renders with on its own,
/// and it has to travel as data because the carousel's `ScrollView` resolves its
/// cells' safe area to zero.
struct MobileSplitCardPage: View {
    let member: BrowserTab
    let space: BrowserSpace
    let pages: MobileBrowserPageStore
    let viewport: MobileBrowserPageViewport
    let prepareMember: (TabID) -> Void
    let handleInteraction: () -> Void

    var body: some View {
        MobileSplitCardContent(
            member: member,
            space: space,
            pages: pages,
            viewport: viewport,
            failureLayout: .compact,
            handleInteraction: handleInteraction
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            prepareMember(member.id)
        }
    }
}
