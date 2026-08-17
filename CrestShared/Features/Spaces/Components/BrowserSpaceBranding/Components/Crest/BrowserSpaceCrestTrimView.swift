import SwiftUI

struct BrowserSpaceCrestTrimView: View {
    let trim: BrowserSpaceCrestTrim
    let outlineSystemImage: String?
    let color: Color
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        switch trim {
        case .none:
            EmptyView()
        case .shield:
            Image(systemName: outlineSystemImage ?? "shield")
                .font(.system(size: size * 0.88, weight: .semibold))
                .foregroundStyle(color)
        case .laurel:
            HStack(spacing: size * 0.26) {
                Image(systemName: "laurel.leading")
                Image(systemName: "laurel.trailing")
            }
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(color)
        case .sunburst:
            Image(systemName: "sun.max")
                .font(.system(size: size * 0.88, weight: .light))
                .foregroundStyle(color)
        case .doubleRing:
            ZStack {
                Circle().stroke(color, lineWidth: max(1, size * 0.025))
                Circle()
                    .stroke(color, lineWidth: max(1, size * 0.018))
                    .padding(size * 0.08)
            }
            .frame(width: size * 0.88, height: size * 0.88)
        case .seal:
            Image(systemName: "seal")
                .font(.system(size: size * 0.88, weight: .medium))
                .foregroundStyle(color)
        }
    }
}
