import SwiftUI

/// A Heraldic sidebar's banner: its pattern laid out in the palette's
/// fills, each one color or a gradient of its own.
struct BrowserSpaceBannerField: View {
    let pattern: SpaceBannerPattern
    let fills: [AnyShapeStyle]
    let size: CGSize

    @ViewBuilder
    var body: some View {
        let first = fills[0]
        let second = fills[min(1, fills.count - 1)]
        let third = fills[min(2, fills.count - 1)]

        switch pattern.kind {
        case .solid:
            Rectangle().fill(first)
        case .split:
            HStack(spacing: 0) {
                Rectangle().fill(first)
                Rectangle().fill(second)
            }
        case .bands:
            VStack(spacing: 0) {
                Rectangle().fill(first)
                Rectangle().fill(second)
                Rectangle().fill(third)
            }
        case .diagonal:
            ZStack {
                Rectangle().fill(first)
                BrowserSpaceDiagonalMiddleBannerShape(size: size)
                    .fill(second)
                BrowserSpaceDiagonalLowerBannerShape(size: size)
                    .fill(third)
            }
        case .chevron:
            ZStack {
                Rectangle().fill(first)
                BrowserSpaceChevronMiddleBannerShape(size: size)
                    .fill(second)
                BrowserSpaceChevronLowerBannerShape(size: size)
                    .fill(third)
            }
        case .stripes, .checkered, .lozenges:
            Canvas { context, canvasSize in
                context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .style(first))
                let cell = max(16, canvasSize.width / 5)
                let rows = min(200, Int(ceil(canvasSize.height / cell)) + 1)
                let columns = min(200, Int(ceil(canvasSize.width / cell)) + 1)
                for row in 0..<rows {
                    for column in 0..<columns {
                        let x = CGFloat(column) * cell
                        let y = CGFloat(row) * cell
                        switch pattern.kind {
                        case .stripes:
                            if column.isMultiple(of: 2) {
                                context.fill(
                                    Path(CGRect(x: x, y: y, width: cell, height: cell)),
                                    with: .style(second.opacity(0.35)))
                            }
                        case .checkered:
                            if (row + column).isMultiple(of: 2) {
                                context.fill(
                                    Path(CGRect(x: x, y: y, width: cell, height: cell)),
                                    with: .style(second.opacity(0.35)))
                            }
                        case .lozenges:
                            var diamond = Path()
                            diamond.move(to: CGPoint(x: x + cell / 2, y: y))
                            diamond.addLine(to: CGPoint(x: x + cell, y: y + cell / 2))
                            diamond.addLine(to: CGPoint(x: x + cell / 2, y: y + cell))
                            diamond.addLine(to: CGPoint(x: x, y: y + cell / 2))
                            diamond.closeSubpath()
                            context.fill(
                                diamond, with: .style(((row + column).isMultiple(of: 2) ? second : third).opacity(0.35))
                            )
                        default: break
                        }
                    }
                }
            }
        case .quartered:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Rectangle().fill(first)
                    Rectangle().fill(second)
                }
                HStack(spacing: 0) {
                    Rectangle().fill(third)
                    Rectangle().fill(first)
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Banner pattern") {
        BrowserSpaceBannerField(
            pattern: .diagonal, fills: [Color.indigo, .cyan, .orange].map { AnyShapeStyle($0) },
            size: CGSize(width: 320, height: 400)
        )
        .frame(width: 320, height: 400)
    }
#endif
