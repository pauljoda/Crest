import SwiftUI

struct BrowserSidebarHoverTracker: NSViewRepresentable {
    var isRevealedByPointer = false
    let onHoverChange: @MainActor @Sendable (Bool) -> Void

    @AppStorage(SidebarEdgeRestHidePreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var storedEdgeRestHideDelay = SidebarEdgeRestHidePreference.defaultValue

    func makeNSView(context: Context) -> BrowserSidebarHoverTrackingView {
        BrowserSidebarHoverTrackingView(onHoverChange: onHoverChange)
    }

    func updateNSView(_ view: BrowserSidebarHoverTrackingView, context: Context) {
        view.onHoverChange = onHoverChange
        view.isRevealedByPointer = isRevealedByPointer
        view.edgeRestHideDelay = SidebarEdgeRestHidePreference.delay(storedEdgeRestHideDelay)
        view.schedulePointerRefresh()
    }
}
