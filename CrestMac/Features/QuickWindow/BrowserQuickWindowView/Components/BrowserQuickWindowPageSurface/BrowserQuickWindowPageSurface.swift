import SwiftUI

struct BrowserQuickWindowPageSurface: View {
    let model: BrowserQuickWindowModel

    var body: some View {
        BrowserRootContentSurface(
            cornerRadius: BrowserQuickWindowLayout.pageCornerRadius,
            seamWidth: BrowserQuickWindowLayout.pageBrandSeamWidth,
            frameInsets: EdgeInsets(
                top: BrowserQuickWindowLayout.pageFrameInset,
                leading: BrowserQuickWindowLayout.pageFrameInset,
                bottom: BrowserQuickWindowLayout.pageFrameInset,
                trailing: BrowserQuickWindowLayout.pageFrameInset
            ),
            usesTransparentInnerSurface:
                model.page == nil
                && model.pageLease?.wasReleasedForMemoryPressure != true
        ) {
            BrowserQuickWindowPageContent(model: model)
        }
        .padding(.top, BrowserQuickWindowLayout.pageTopClearance)
    }
}
