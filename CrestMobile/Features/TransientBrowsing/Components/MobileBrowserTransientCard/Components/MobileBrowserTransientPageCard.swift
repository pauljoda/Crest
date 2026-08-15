import SwiftUI

struct MobileBrowserTransientPageCard: View {
    let model: MobileBrowserTransientOverlayModel
    let isPhone: Bool
    let reduceTransparency: Bool

    var body: some View {
        Group {
            if let page = model.page {
                MobileBrowserWebView(page: page)
                    .id(page.tabID)
            } else if model.pageLease?.wasReleasedForMemoryPressure == true {
                MobileBrowserTransientReleasedPageView(
                    isQuickWindow: model.request.isQuickWindow,
                    restore: model.restorePage
                )
            } else {
                MobileBrowserTransientLoadingPageView(
                    isQuickWindow: model.request.isQuickWindow
                )
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(
            color: .black.opacity(reduceTransparency ? 0 : 0.32),
            radius: 24,
            y: 12
        )
    }

    private var cornerRadius: CGFloat {
        isPhone ? 24 : 15
    }
}

#Preview {
    MobileBrowserTransientPageCard(
        model: MobileBrowserTransientPreviewFixture.makeModel(),
        isPhone: true,
        reduceTransparency: false
    )
    .frame(width: 340, height: 520)
}
