import AppKit

extension BrowserSpacePagerPolicy {
    @MainActor
    static func hideHorizontalScroller(in scrollView: NSScrollView) {
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScroller = nil
    }
}
