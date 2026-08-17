import SwiftUI

struct MobileBrowserTransientReleasedPageView: View {
    let isQuickWindow: Bool
    let restore: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "memorychip")
        } description: {
            Text("Crest released this temporary page to reduce memory use.")
        } actions: {
            Button("Reload Page", action: restore)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private var title: String {
        isQuickWindow ? "Quick Window Released" : "Peek Released"
    }
}
