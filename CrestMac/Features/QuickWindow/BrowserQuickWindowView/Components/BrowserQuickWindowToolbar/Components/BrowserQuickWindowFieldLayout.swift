import SwiftUI

/// Lays out a Quick Window's address field and the pinned extensions after it
/// in the width the toolbar leaves them: the extensions are offered what the
/// field leaves beyond `widthBeforeExtensions`, showing as many as fit, and
/// the field takes the rest. Without extensions the field takes it all, and it
/// is never narrower than `fieldMinimumWidth`.
struct BrowserQuickWindowFieldLayout: Layout {
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
        // Never narrower than the field's minimum and the extensions' own,
        // the overflow button alone, beside it.
        let extensions = subviews.dropFirst().first?.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width ?? 0
        let minimum = fieldMinimumWidth + (extensions > 0 ? spacing + extensions : 0)
        return CGSize(width: max(width, minimum), height: proposal.height ?? height)
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
