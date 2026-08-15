import SwiftUI

struct MobileNavigationHistoryMenu: View {
    let items: [BrowserNavigationHistoryItem]
    let emptyTitle: String
    let action: (BrowserNavigationHistoryItem) -> Void

    var body: some View {
        if items.isEmpty {
            Text(emptyTitle)
        } else {
            ForEach(items) { item in
                Button {
                    action(item)
                } label: {
                    Label(item.title, systemImage: "globe")
                }
            }
        }
    }
}

#Preview("Navigation History") {
    MobileNavigationHistoryMenu(
        items: [
            BrowserNavigationHistoryItem(
                depth: 1,
                title: "Apple Developer",
                url: URL(fileURLWithPath: "/preview/apple-developer")
            ),
            BrowserNavigationHistoryItem(
                depth: 2,
                title: "WebKit",
                url: URL(fileURLWithPath: "/preview/webkit")
            ),
        ],
        emptyTitle: "No Earlier Pages",
        action: { _ in }
    )
    .padding()
    .frame(width: 280)
}
