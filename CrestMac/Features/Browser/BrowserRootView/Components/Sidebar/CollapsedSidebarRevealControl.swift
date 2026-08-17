import SwiftUI

struct CollapsedSidebarRevealControl: View {
    let showSidebar: () -> Void

    var body: some View {
        Button(action: showSidebar) {
            Color.clear
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show Sidebar Temporarily")
        .help("Move the pointer to the leading edge to preview the sidebar")
        .onHover { isHovering in
            guard isHovering else { return }
            showSidebar()
        }
        .frame(width: BrowserRootMetrics.collapsedSidebarRevealWidth)
        .frame(maxHeight: .infinity)
    }
}
