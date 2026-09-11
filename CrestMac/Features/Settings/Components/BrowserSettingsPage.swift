import AppKit
import SwiftUI

/// Compact, consistent page chrome. Each pane owns its scrolling surface.
struct BrowserSettingsPage<Content: View>: View {
    let destination: BrowserSettingsDestination
    @ViewBuilder let content: Content

    init(
        destination: BrowserSettingsDestination,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if destination != .spaces {
                BrowserSettingsCompactPageIdentity(destination: destination)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(BrowserSettingsCanvas.background)
        .controlSize(.regular)
    }
}
