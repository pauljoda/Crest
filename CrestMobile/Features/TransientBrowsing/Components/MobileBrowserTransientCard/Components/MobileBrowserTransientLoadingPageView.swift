import SwiftUI

struct MobileBrowserTransientLoadingPageView: View {
    let isQuickWindow: Bool

    var body: some View {
        ProgressView(
            isQuickWindow ? "Opening Quick Window…" : "Opening Peek…"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

#Preview {
    MobileBrowserTransientLoadingPageView(isQuickWindow: false)
}
