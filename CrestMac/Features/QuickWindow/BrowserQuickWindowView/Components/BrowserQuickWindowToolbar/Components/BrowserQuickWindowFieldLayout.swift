import SwiftUI

/// Lays out a Quick Window's address field and the pinned extensions after it
/// in the width the toolbar leaves them: the extensions are offered what the
/// field's minimum leaves, showing as many as fit, and the field takes the
/// rest. Without extensions the field takes it all.
struct BrowserQuickWindowFieldLayout: Layout {
    // MARK: - Variables

    let fieldMinimumWidth: CGFloat
    let spacing: CGFloat

    // MARK: - Actions - Layout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        guard let width = proposal.width else {
            let extensions = subviews.dropFirst().first?.sizeThatFits(.unspecified).width ?? 0
            return CGSize(width: fieldMinimumWidth + (extensions > 0 ? spacing + extensions : 0), height: height)
        }
        return CGSize(width: width, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let field = subviews.first else { return }
        var fieldWidth = bounds.width
        if let extensions = subviews.dropFirst().first {
            let offered = max(0, bounds.width - fieldMinimumWidth - spacing)
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
