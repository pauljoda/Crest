import SwiftUI

/// A group's name at the size Tab size gives the sidebar: small and semibold,
/// as a caption is beside the sidebar's text, and growing or shrinking with it.
struct BrowserGroupNameFont: ViewModifier {
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @ScaledMetric(relativeTo: .caption) private var textSizeScale = 1.0
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    func body(content: Content) -> some View {
        let size =
            BrowserSidebarDensity.captionSize(touch: capabilities.supportsTouch) * textSizeScale
            * BrowserSidebarDensity(tabScale).contentScale
        content.font(.system(size: size, weight: .semibold))
    }
}
