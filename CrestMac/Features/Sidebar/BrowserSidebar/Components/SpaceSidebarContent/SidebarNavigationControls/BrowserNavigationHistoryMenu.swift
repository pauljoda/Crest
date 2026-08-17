import SwiftUI

struct BrowserNavigationHistoryMenu: View {
    let items: [BrowserNavigationHistoryItem]
    let emptyTitle: LocalizedStringKey
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
                .help(item.url.absoluteString)
            }
        }
    }
}
