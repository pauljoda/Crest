import SwiftUI

struct BrowserPlatformHorizontalScrollerSuppressor: NSViewRepresentable {
    func makeNSView(
        context: Context
    ) -> BrowserPlatformHorizontalScrollerObserverView {
        BrowserPlatformHorizontalScrollerObserverView()
    }

    func updateNSView(
        _ nsView: BrowserPlatformHorizontalScrollerObserverView,
        context: Context
    ) {
        nsView.scheduleHorizontalScrollerSuppression()
    }
}

#Preview("Horizontal Scroller Suppressor") {
    BrowserPlatformHorizontalScrollerSuppressor()
        .frame(width: 320, height: 120)
}
