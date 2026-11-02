import SwiftUI

struct BrowserQuickWindowPageSurface: View {
    @Environment(\.browserWindowCornerRadius) private var windowCornerRadius
    @Environment(\.layoutDirection) private var layoutDirection
    let model: BrowserQuickWindowModel

    private var appearance: BrowserChromeAppearance { .device(windowCornerRadius: windowCornerRadius) }

    var body: some View {
        BrowserRootContentSurface(
            cornerRadius: appearance.pageCornerRadius,
            seamWidth: appearance.seamWidth,
            frameInsets: frameInsets,
            usesTransparentInnerSurface:
                model.page == nil
                && model.pageLease?.wasReleasedForMemoryPressure != true,
            showsBoundary: !appearance.borderless
        ) {
            BrowserQuickWindowPageContent(model: model)
        }
    }

    private var frameInsets: EdgeInsets {
        var insets = appearance.pageInsets(docked: false, direction: layoutDirection)
        // The page shows as far below the toolbar as the toolbar sits below
        // the window's top, its seam included, so the controls sit centred
        // between the two.
        insets.top = BrowserQuickWindowLayout.toolbarTopPadding - appearance.seamWidth
        return insets
    }
}
