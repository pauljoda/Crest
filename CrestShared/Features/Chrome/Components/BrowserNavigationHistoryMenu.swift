import SwiftUI

/// One page's back or forward stack, as menu items.
///
/// Shared by every chrome that hangs history off a navigation control — the
/// sidebar strip on both shells, and the compact shell's floating history
/// capsule.
struct BrowserNavigationHistoryMenu: View {
    let items: [BrowserNavigationHistoryItem]
    let emptyTitle: LocalizedStringKey
    let action: (BrowserNavigationHistoryItem) -> Void

    var body: some View {
        Group {
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
        .crestMenuActionLabelStyle()
    }
}
