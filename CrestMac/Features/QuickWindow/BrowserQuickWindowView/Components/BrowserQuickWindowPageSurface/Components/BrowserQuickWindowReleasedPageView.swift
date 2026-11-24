import SwiftUI

struct BrowserQuickWindowReleasedPageView: View {
    let reduceTransparency: Bool
    let restore: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Quick Window Released").font(CrestTypography.displayPage)
            } icon: {
                Image(systemName: "memorychip")
            }
        } description: {
            Text("Crest released this temporary page to reduce memory use.")
        } actions: {
            Button("Reload Page", action: restore)
                .buttonStyle(.crestPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(CrestBrandTheme.canvas.opacity(reduceTransparency ? 1 : 0.9))
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserQuickWindowReleasedPageView(reduceTransparency: false, restore: {}).frame(width: 540, height: 360)
    }
#endif
