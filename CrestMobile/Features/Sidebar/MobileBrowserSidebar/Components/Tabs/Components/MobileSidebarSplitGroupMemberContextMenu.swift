import SwiftUI

/// The per-member menu on a stacked group row.
///
/// Deliberately narrow: it offers only what is specific to *this* line's
/// membership. Everything a tab can do regardless of a split stays on the shared
/// tab menu, so there is one place that owns tab organization.
struct MobileSidebarSplitGroupMemberContextMenu: View {
    let configuration: MobileSidebarSplitGroupRowConfiguration
    let member: BrowserTab

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        // The same two literals the shared tab menu uses, because a long press
        // on iPhone and a right-click on the Mac are the same offer.
        moveButton(.left, title: "Move Left", systemImage: "arrow.left")
        moveButton(.right, title: "Move Right", systemImage: "arrow.right")

        Button("Remove from Split", systemImage: "rectangle.badge.minus") {
            guard configuration.isCurrentAndUnlocked else { return }
            configuration.browser.removeTabFromSplit(
                member.id,
                matching: configuration.assignment
            )
        }
        .disabled(!configuration.isCurrentAndUnlocked)
    }

    /// "Left" and "Right" name the carousel as the person sees it, so the member
    /// offset flips under a right-to-left layout — the stacked lines and the
    /// cards share one member order. See `BrowserSplitCardMoveDirection`.
    private func moveButton(
        _ direction: BrowserSplitCardMoveDirection,
        title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        let offset = direction.memberOffset(layoutDirection: layoutDirection)
        return Button(title, systemImage: systemImage) {
            guard configuration.isCurrentAndUnlocked else { return }
            configuration.browser.moveSplitMember(
                member.id,
                by: offset,
                matching: configuration.assignment
            )
        }
        .disabled(
            !configuration.isCurrentAndUnlocked
                || !configuration.browser.canMoveSplitMember(
                    member.id,
                    by: offset,
                    matching: configuration.assignment
                )
        )
    }
}

#Preview("Mobile Split Member Menu", traits: .sizeThatFitsLayout) {
    let configuration = MobileSidebarSplitGroupRowPreviewFixture.configuration()

    Menu("Open Member Actions", systemImage: "ellipsis.circle") {
        MobileSidebarSplitGroupMemberContextMenu(
            configuration: configuration,
            member: configuration.members[0]
        )
    }
    .padding()
}
