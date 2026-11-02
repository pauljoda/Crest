import SwiftUI

/// A Space's pinned extension actions in a Quick Window's toolbar: as many of
/// the buttons the sidebar's strip shows as fit beside the address field, and
/// the rest behind one overflow button.
struct BrowserPinnedExtensionToolbarActions: View {
    // MARK: - Static Variables

    private static let spacing: CGFloat = 2

    // MARK: - Variables

    let actions: [BrowserExtensionActionPresentation]
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    var prepare: (BrowserExtensionActionPresentation) -> Void = { _ in }
    var presentMenu: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void = { _, _ in }

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
        HStack(spacing: Self.spacing) {
            ForEach(actions.prefix(shown)) { action in
                BrowserPinnedExtensionActionButton(
                    action: action,
                    perform: { perform(action, $0) },
                    prepare: { prepare(action) },
                    presentMenu: { presentMenu(action, $0) }
                )
            }
            if shown < actions.count {
                BrowserPinnedExtensionOverflowButton(
                    actions: Array(actions.dropFirst(shown)),
                    perform: perform,
                    prepare: prepare
                )
            }
        }
    }
}
