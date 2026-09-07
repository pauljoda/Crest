import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct TabFaviconContent: View {
    @Environment(\.browserApplicationIcon) private var applicationIcon

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
            } else if tab.nativeContent == .gettingStarted {
                #if os(macOS)
                    (applicationIcon ?? Image(nsImage: NSApplication.shared.applicationIconImage))
                        .resizable().interpolation(.high).scaledToFit()
                #else
                    CrestStartPageMark()
                #endif
            } else if tab.nativeContent != nil {
                Image(systemName: tab.symbol).symbolRenderingMode(.hierarchical)
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
