import SwiftUI

struct TabFaviconContent: View {
    let tab: BrowserTab
    let size: CGFloat
    let requestIdentity: BrowserFaviconTaskIdentity
    let renderedImage: BrowserFaviconRenderedImage?

    var body: some View {
        Group {
            if tab.isStartPage {
                CrestStartPageMark()
            } else if let emoji = tab.emojiIcon {
                Text(emoji)
                    .font(.system(size: size * TabFaviconMetrics.emojiSizeRatio))
                    .minimumScaleFactor(TabFaviconMetrics.emojiMinimumScaleFactor)
            } else if let image = renderedImage?.image(matching: requestIdentity) {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(
                        .rect(cornerRadius: TabFaviconMetrics.cornerRadius(for: size))
                    )
            } else {
                Image(systemName: "globe")
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }
}

#Preview("Tab Favicon Content — Image") {
    let request = BrowserFaviconTaskIdentityPolicy.renderRequest(
        for: TabFaviconPreviewFixture.image,
        profileID: TabFaviconPreviewFixture.profileID,
        maximumPixelSize: 64
    )
    TabFaviconContent(
        tab: TabFaviconPreviewFixture.image,
        size: 48,
        requestIdentity: request.identity,
        renderedImage: TabFaviconPreviewFixture.renderedImage(
            for: request.identity,
            maximumPixelSize: 64
        )
    )
    .frame(width: 48, height: 48)
    .padding()
}
