import SwiftUI

struct MobileBrowserSidebarBottomChromeLayout<Content: View>: View {
    let configuration: MobileBrowserSidebarContentConfiguration
    let content: Content

    init(
        configuration: MobileBrowserSidebarContentConfiguration,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.content = content()
    }

    var body: some View {
        switch MobileBrowserSidebarBottomChromePolicy.placement(
            reservesInset: configuration.reservesBottomChromeInset,
            isVisible: configuration.showsBottomSpaceSwitcher
        ) {
        case .hidden:
            content
        case .inlineSafeAreaInset:
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MobileBrowserSidebarBottomChrome(
                        configuration: configuration
                    )
                }
        }
    }
}
