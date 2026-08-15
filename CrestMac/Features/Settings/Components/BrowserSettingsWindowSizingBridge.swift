import AppKit
import SwiftUI

struct BrowserSettingsWindowSizingBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> BrowserSettingsWindowSizingHostView {
        BrowserSettingsWindowSizingHostView()
    }

    func updateNSView(
        _ nsView: BrowserSettingsWindowSizingHostView,
        context: Context
    ) {
        nsView.applyWindowSizing()
    }
}
