import SwiftUI

/// Lays views out in rows no wider than the room offered, each row aligned
/// to the leading edge or centered, so chips wrap rather than run off.
struct CrestFlowLayout: Layout {
    // MARK: - Types

    /// The views one row holds, and how wide and tall the row is.
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    // MARK: - Variables

    /// The room between two views in a row, and between rows.
    let gap: CGFloat
    /// Where each row sits across the room offered.
    var alignment: HorizontalAlignment = .leading

    // MARK: - Actions - Layout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, within: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + gap * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, within: bounds.width) {
            var x = bounds.minX + (alignment == .center ? (bounds.width - row.width) / 2 : 0)
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + gap
            }
            y += row.height + gap
        }
    }

    // MARK: - Actions - Reading

    /// The views in rows, each taking views while they fit within `width`.
    private func rows(of subviews: Subviews, within width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let widened = row.indices.isEmpty ? size.width : row.width + gap + size.width
            if !row.indices.isEmpty, widened > width {
                rows.append(row)
                row = Row(indices: [index], width: size.width, height: size.height)
            } else {
                row.indices.append(index)
                row.width = widened
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
