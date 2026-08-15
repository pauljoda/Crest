import SwiftUI

struct BrowserRootUtilityFanLayer: View {
    let model: BrowserRootModel

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { proxy in
            if let triggerFrame = model.chrome.utilityPresentation
                .triggerFrameInGlobal,
                model.sidebarPresentation.showsSidebar
            {
                BrowserRootUtilityFanControl(
                    model: model,
                    proxy: proxy,
                    triggerFrame: triggerFrame,
                    layoutDirection: layoutDirection
                )
            }
        }
    }
}

#Preview("Browser Root Utility Fan Layer") {
    BrowserRootUtilityFanLayer(model: BrowserRootPreviewFixture.makeModel())
        .frame(width: 480, height: 320)
}
