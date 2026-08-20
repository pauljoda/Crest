import SwiftUI

struct MobileBrowserSidebarChrome: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        VStack(spacing: 0) {
            MobileBrowserSidebarTopChrome(configuration: configuration)

            BrowserSpaceSwitcher(
                browser: configuration.browser,
                downloadCenter: configuration.pages.downloadCenter,
                capabilities: capabilities,
                selectSpace: configuration.selectSpace
            )
        }
    }

    /// What this shell can do, until the shell itself hands it down: a finger
    /// is the primary input, and a trackpad may still be attached.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities(
            supportsHover: true,
            supportsTouch: true,
            showsRowDropIndicators: true,
            reservesReorderSectionZones: true,
            usesNativeNavigationTransition: configuration.mode
                == .compactTabViewer
        )
    }
}
