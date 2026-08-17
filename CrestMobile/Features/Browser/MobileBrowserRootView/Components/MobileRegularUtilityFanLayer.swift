import SwiftUI

struct MobileRegularUtilityFanLayer: View {
    let layout: MobileRegularWindowLayout
    let layoutDirection: LayoutDirection
    let triggerFrameInGlobal: CGRect?
    let sidebarIsPresented: Bool
    let isExpanded: Bool
    let selectedSurface: BrowserUtilitySurface?
    let badgeColor: Color
    let downloads: [BrowserDownloadItem]
    let newDownloadCount: Int
    let select: (BrowserUtilitySurface) -> Void

    var body: some View {
        GeometryReader { proxy in
            if let triggerFrameInGlobal, sidebarIsPresented {
                let rootFrame = proxy.frame(in: .global)
                let localTriggerFrame = triggerFrameInGlobal.offsetBy(
                    dx: -rootFrame.minX,
                    dy: -rootFrame.minY
                )
                let edgeOffset =
                    BrowserUtilitySwitcherLayout.buttonSize / 2
                    + BrowserUtilitySwitcherLayout.destinationGap
                let destinationX =
                    switch layoutDirection {
                    case .leftToRight:
                        layout.sidebarWidth + edgeOffset
                    case .rightToLeft:
                        proxy.size.width - layout.sidebarWidth - edgeOffset
                    @unknown default:
                        layout.sidebarWidth + edgeOffset
                    }

                BrowserUtilityFanControl(
                    isExpanded: isExpanded,
                    origin: CGPoint(
                        x: localTriggerFrame.midX,
                        y: localTriggerFrame.midY
                    ),
                    destination: CGPoint(
                        x: destinationX,
                        y: proxy.size.height / 2
                    ),
                    selectedSurface: selectedSurface,
                    badgeColor: badgeColor,
                    downloads: downloads,
                    newDownloadCount: newDownloadCount,
                    select: select
                )
                .zIndex(MobileBrowserRootLayout.utilityLayer)
            }
        }
    }
}
