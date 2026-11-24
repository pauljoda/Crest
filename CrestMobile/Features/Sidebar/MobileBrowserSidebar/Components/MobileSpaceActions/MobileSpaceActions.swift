import SwiftUI

/// The Space's own controls in one floating capsule, after any controls
/// `leading` puts in front of them. Offered less than its ideal width, it
/// narrows its buttons to fit.
struct MobileSpaceActions<Leading: View>: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let utilityPresentationStyle: MobileBrowserSidebarUtilityPresentationStyle
    let configuration: MobileSpaceActionsConfiguration
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 0) {
            leading
            MobileSpaceActionButtons(
                browser: browser,
                pages: pages,
                utilityPresentationStyle: utilityPresentationStyle,
                configuration: configuration
            )
        }
        .labelStyle(.iconOnly)
        .buttonStyle(MobileSpaceUtilityButtonLabel.capsuleButtonStyle)
        .controlSize(.large)
        .padding(CrestSpacing.extraSmall)
        .glassEffect(.regular, in: .capsule)
    }
}

extension MobileSpaceActions where Leading == EmptyView {
    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        utilityPresentationStyle: MobileBrowserSidebarUtilityPresentationStyle,
        configuration: MobileSpaceActionsConfiguration
    ) {
        self.init(
            browser: browser, pages: pages, utilityPresentationStyle: utilityPresentationStyle,
            configuration: configuration, leading: { EmptyView() })
    }
}
