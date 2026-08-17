import SwiftUI

struct MobileTransientBrowsingPreviewSurface: View {
    let request: MobileBrowserTransientRequest

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: CrestSpacing.medium) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                Text(request.accessibilityLabel)
                    .font(.headline)
            }
            .padding(CrestSpacing.extraLarge)
            .background {
                RoundedRectangle(cornerRadius: CrestRadius.panel)
                    .fill(.regularMaterial)
            }
        }
    }

    private var systemImage: String {
        request.isQuickWindow ? "sparkle.magnifyingglass" : "eye"
    }
}
