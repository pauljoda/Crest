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
