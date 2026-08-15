import SwiftUI

struct BrowserPeekLoadingPageView: View {
    var body: some View {
        ProgressView("Opening Peek…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
    }
}

#Preview {
    BrowserPeekLoadingPageView()
        .frame(width: 640, height: 420)
}
