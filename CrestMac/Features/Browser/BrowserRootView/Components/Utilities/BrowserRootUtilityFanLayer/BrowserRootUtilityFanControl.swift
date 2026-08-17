import SwiftUI

struct BrowserRootUtilityFanControl: View {
    let model: BrowserRootModel
    let proxy: GeometryProxy
    let triggerFrame: CGRect
    let layoutDirection: LayoutDirection

    private var localTriggerFrame: CGRect {
        let rootFrame = proxy.frame(in: .global)
        return triggerFrame.offsetBy(
            dx: -rootFrame.minX,
            dy: -rootFrame.minY
        )
    }

    private var destinationX: CGFloat {
        let edgeOffset =
            BrowserUtilitySwitcherLayout.buttonSize / 2
            + BrowserUtilitySwitcherLayout.destinationGap
            + BrowserRootMetrics.utilityFanAdditionalEdgeOffset
        switch layoutDirection {
        case .leftToRight:
            return localTriggerFrame.maxX + edgeOffset
        case .rightToLeft:
            return localTriggerFrame.minX - edgeOffset
        @unknown default:
            return localTriggerFrame.maxX + edgeOffset
        }
    }

    var body: some View {
        BrowserUtilityFanControl(
            isExpanded: model.chrome.utilityPresentation.isSwitcherExpanded,
            origin: CGPoint(
                x: localTriggerFrame.midX,
                y: localTriggerFrame.midY
            ),
            destination: CGPoint(
                x: destinationX,
                y: proxy.size.height / 2
            ),
            selectedSurface: model.chrome.utilityPresentation.surface,
            badgeColor: model.browser.selectedSpace?.branding.colors.first?.color
                ?? .accentColor,
            downloads: model.selectedUtilityDownloads,
            newDownloadCount: model.newUtilityDownloads.count,
            select: model.chrome.utilityPresentation.present
        )
        .zIndex(BrowserRootMetrics.utilityFanZIndex)
    }
}
