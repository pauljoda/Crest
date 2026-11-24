import AppKit
import SwiftUI

struct BrowserRootUtilityFanLayer: View {
    let model: BrowserRootModel
    var sidebarOnRight = false

    @State private var visibleTriggerFrame: CGRect?

    var body: some View {
        GeometryReader { proxy in
            if let triggerFrame = model.chrome.utilityPresentation
                .triggerFrameInGlobal
            {
                let rootFrame = proxy.frame(in: .global)
                let localTriggerFrame = triggerFrame.offsetBy(
                    dx: -rootFrame.minX,
                    dy: -rootFrame.minY
                )
                BrowserRootUtilityFanControl(
                    model: model,
                    proxy: proxy,
                    localTriggerFrame:
                        model.sidebarPresentation.reservesSidebarWidth
                        ? localTriggerFrame : visibleTriggerFrame ?? localTriggerFrame,
                    sidebarOnRight: sidebarOnRight
                )
                .onChange(of: localTriggerFrame, initial: true) { _, frame in
                    guard !model.sidebarPresentation.reservesSidebarWidth,
                        model.sidebarPresentation.showsSidebar
                    else { return }
                    visibleTriggerFrame = frame
                }
            }
        }
        .animation(nil, value: model.sidebarPresentation)
    }
}
