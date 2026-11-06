import SwiftUI

struct MobileBrowserSidebarChrome: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        VStack(spacing: 0) {
            MobileBrowserSidebarTopChrome(configuration: configuration)

            BrowserSpaceSwitcher(
                browser: configuration.context.browser,
                downloadCenter: configuration.context.pageAccess.downloadCenter,
                capabilities: configuration.context.capabilities,
                selectSpace: configuration.context.selectSpace
            )
        }
        .modifier(
            SpaceForegroundBlend(
                spaces: configuration.context.availableSpaces,
                selectedSpaceID: configuration.context.browser.shownSpace?.id)
        )
        // A touch lift is a system drag session, and it reaches only the drop
        // interactions it passes over. The Space pages below feed their own
        // lists; without a feed here the picker never sees the pointer, and a
        // tab cannot be dropped on a Space.
        .modifier(
            MobileBrowserReorderDropFeed(
                browser: configuration.context.browser,
                spaceAccess: configuration.context.spaceAccess
            )
        )
        // The system draws the dragged preview on a touch device, so the reason a
        // Space refuses the tab is shown here, under the picker, while the finger
        // is over it. Releasing ends the drag and clears it with the refusal.
        .overlay(alignment: .bottom) {
            if let message = sidebarInteraction.sidebarReorderState.constraintMessage {
                Label(message, systemImage: "nosign")
                    .font(CrestTypography.metadata)
                    .padding(CrestSpacing.small)
                    .frame(maxWidth: 280, alignment: .leading)
                    .background {
                        CrestSurfaceLayer(shape: .rect(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: 0)))
                    }
                    .alignmentGuide(.bottom) { $0[.top] - CrestSpacing.small }
                    .allowsHitTesting(false)
            }
        }
    }
}
