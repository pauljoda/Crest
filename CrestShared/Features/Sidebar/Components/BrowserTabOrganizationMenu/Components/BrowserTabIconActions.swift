import SwiftUI

struct BrowserTabIconActions: View {
    let tab: BrowserTab
    let isLoaded: Bool
    let pullNewIcon: (() -> Void)?
    let performIfCurrent: ((BrowserTab) -> Void) -> Void
    let clearIcon: (BrowserTab) -> Void
    let changeIcon: (BrowserTab) -> Void

    var body: some View {
        if tab.nativeContent == nil {
            Button("Pull New Icon", systemImage: "arrow.clockwise.circle") {
                performIfCurrent { _ in pullNewIcon?() }
            }
            .disabled(!isLoaded || pullNewIcon == nil)

        }

        Button("Clear Icon", systemImage: "xmark.circle") {
            performIfCurrent(clearIcon)
        }
        .disabled(tab.iconMode == .automatic && tab.faviconData == nil)

        Button("Change Icon…", systemImage: "face.smiling") {
            performIfCurrent(changeIcon)
        }
    }
}

enum BrowserTabIconCustomizationPolicy {
    /// Reset applies to explicit icon overrides.
    static func showsReset(for tab: BrowserTab) -> Bool {
        tab.iconMode != .automatic
    }
}
