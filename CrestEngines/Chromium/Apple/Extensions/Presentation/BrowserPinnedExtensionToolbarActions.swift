import SwiftUI

/// A Space's pinned extension actions in a Quick Window's toolbar: as many of
/// the buttons the sidebar's strip shows as fit beside the address field, and
/// the rest in an overflow that drops down below them. An action run from the
/// overflow moves out to the toolbar's last place, and its popup opens from
/// there in the same click.
struct BrowserPinnedExtensionToolbarActions: View {
    // MARK: - Static Variables

    private static let spacing: CGFloat = 2

    // MARK: - Variables

    let actions: [BrowserExtensionActionPresentation]
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    var prepare: (BrowserExtensionActionPresentation) -> Void = { _ in }
    var presentMenu: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void = { _, _ in }

    /// The action last run from the overflow, which keeps the toolbar's last
    /// place while the Quick Window is open.
    @State private var promotedID: String?
    /// The promoted action's run, which waits for its button to be on screen.
    @State private var pendingRunID: String?

    var body: some View {
        // The first row that fits wins: every action, then one fewer beside
        // the overflow button, down to the overflow button alone.
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: actions.count, through: 0, by: -1)), id: \.self) { shown in
                row(showing: shown)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned Extensions")
    }

    private func row(showing shown: Int) -> some View {
        let (visible, overflow) = arrangement(showing: shown)
        return HStack(spacing: Self.spacing) {
            ForEach(visible) { action in
                BrowserPinnedExtensionActionButton(
                    action: action,
                    perform: { anchor in
                        pendingRunID = nil
                        perform(action, anchor)
                    },
                    prepare: { prepare(action) },
                    presentMenu: { presentMenu(action, $0) },
                    performsOnceAnchored: pendingRunID == action.id
                )
            }
            if !overflow.isEmpty {
                BrowserPinnedExtensionOverflowButton(
                    actions: overflow,
                    prepare: prepare,
                    choose: { action in
                        // With no place in the toolbar to move to, the action
                        // opens its popup from the overflow button instead.
                        guard !visible.isEmpty else { return false }
                        promotedID = action.id
                        pendingRunID = action.id
                        return true
                    },
                    perform: perform
                )
            }
        }
    }

    /// The actions a row showing `shown` of them holds, and the ones its
    /// overflow holds: pinned order, except that the promoted action takes
    /// the last place the row shows.
    private func arrangement(
        showing shown: Int
    ) -> (visible: [BrowserExtensionActionPresentation], overflow: [BrowserExtensionActionPresentation]) {
        let ordered = (Array(actions.prefix(shown)), Array(actions.dropFirst(shown)))
        guard shown > 0, let promoted = ordered.1.first(where: { $0.id == promotedID }) else { return ordered }
        let visible = Array(actions.prefix(shown - 1)) + [promoted]
        return (visible, actions.filter { action in !visible.contains { $0.id == action.id } })
    }
}
