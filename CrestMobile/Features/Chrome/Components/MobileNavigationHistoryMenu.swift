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
