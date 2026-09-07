import SwiftUI

struct BrowserSidebarHoverTracker: NSViewRepresentable {
    let isEnabled: Bool
    let onHoverChange: @MainActor @Sendable (Bool) -> Void

    func makeNSView(context: Context) -> BrowserSidebarHoverTrackingView {
        let view = BrowserSidebarHoverTrackingView(onHoverChange: onHoverChange)
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ view: BrowserSidebarHoverTrackingView, context: Context) {
        view.onHoverChange = onHoverChange
        view.isEnabled = isEnabled
        view.schedulePointerRefresh()
    }
}
