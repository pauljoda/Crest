import SwiftUI

/// Crest's mark on its tile, as square as the space it is given allows,
/// under a rim one device pixel wide, so the rim stays even at every size
/// and display scale.
struct CrestStartPageMark: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let palette = CrestStartPageMarkPalette(colorScheme: colorScheme)

            ZStack {
                RoundedRectangle(
                    cornerRadius: side * CrestStartPageMarkMetrics.cornerRadiusRatio,
                    style: .continuous
                )
                .fill(palette.background)

                ZStack {
                    CrestBannerShape()
                        .fill(palette.coral)

                    CrestButterPlaneShape()
                        .fill(palette.butter)

                    CrestSkyPlaneShape()
                        .fill(palette.sky)

                    Rectangle()
                        .fill(palette.rail)
                        .frame(width: side * CrestStartPageMarkMetrics.railWidthRatio)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipShape(CrestBannerShape())

                RoundedRectangle(
                    cornerRadius: side * CrestStartPageMarkMetrics.cornerRadiusRatio,
                    style: .continuous
                )
                .strokeBorder(.primary.opacity(CrestStartPageMarkMetrics.borderOpacity), lineWidth: 1 / displayScale)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

#if DEBUG
    #Preview("Component") {
        CrestStartPageMark().frame(width: 80, height: 80).padding()
    }
#endif
