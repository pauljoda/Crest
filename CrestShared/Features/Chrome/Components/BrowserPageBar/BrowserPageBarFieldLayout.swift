import SwiftUI

/// Lays out a page bar's address field and the pinned extensions after it
/// in the width the toolbar leaves them: the extensions are offered what the
/// field leaves beyond `widthBeforeExtensions`, showing as many as fit, and
/// the field takes the rest. Without extensions the field takes it all.
///
/// The field keeps `fieldMinimumWidth` while the bar has room for it, and
/// gives way below it in a bar too narrow for its controls, such as a split's
/// leading card at its narrowest beside the window's buttons, rather than push
/// the bar past its edges.
struct BrowserPageBarFieldLayout: Layout {
    // MARK: - Variables

    let fieldMinimumWidth: CGFloat
    let widthBeforeExtensions: CGFloat
    let spacing: CGFloat

    // MARK: - Actions - Layout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        guard let width = proposal.width else {
            let extensions = subviews.dropFirst().first?.sizeThatFits(.unspecified).width ?? 0
            return CGSize(width: widthBeforeExtensions + (extensions > 0 ? spacing + extensions : 0), height: height)
        }
        // The field's minimum and the extensions' own, the overflow button
        // alone, beside it, as far as the bar has the room.
        let extensions = subviews.dropFirst().first?.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width ?? 0
        let minimum = fieldMinimumWidth + (extensions > 0 ? spacing + extensions : 0)
        return CGSize(width: width > 0 ? width : minimum, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let field = subviews.first else { return }
        var fieldWidth = bounds.width
        if let extensions = subviews.dropFirst().first {
            let offered = max(0, bounds.width - widthBeforeExtensions - spacing)
            let width = extensions.sizeThatFits(ProposedViewSize(width: offered, height: bounds.height)).width
            if width > 0 {
                fieldWidth = bounds.width - width - spacing
                extensions.place(
                    at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                    proposal: ProposedViewSize(width: width, height: bounds.height))
            }
        }
        field.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
            proposal: ProposedViewSize(width: fieldWidth, height: bounds.height))
    }
}
