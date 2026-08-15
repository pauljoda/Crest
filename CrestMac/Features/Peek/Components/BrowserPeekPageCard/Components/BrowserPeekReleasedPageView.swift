import SwiftUI

struct BrowserPeekReleasedPageView: View {
    let restore: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Peek Released", systemImage: "memorychip")
        } description: {
            Text("Crest released this temporary page to reduce memory use.")
        } actions: {
            Button("Reload Peek", action: restore)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

#Preview {
    BrowserPeekReleasedPageView(restore: {})
        .frame(width: 640, height: 420)
}
