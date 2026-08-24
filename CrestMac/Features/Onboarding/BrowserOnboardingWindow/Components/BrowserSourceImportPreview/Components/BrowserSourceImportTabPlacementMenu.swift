import SwiftUI

struct BrowserSourceImportTabPlacementMenu: View {
    let tab: BrowserTab
    let setPlacement: (TabID, TabPlacement) -> Void

    var body: some View {
        Menu {
            Group {
                Button("Pinned", systemImage: "pin.fill") {
                    setPlacement(tab.id, .pinned)
                }
                Button("Saved", systemImage: "bookmark.fill") {
                    setPlacement(tab.id, .saved)
                }
                Button("Open", systemImage: "rectangle") {
                    setPlacement(tab.id, .current)
                }
            }
            .crestMenuActionLabelStyle()
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 22, height: 22)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .crestMenuActionLabelStyle()
        .fixedSize()
        .accessibilityLabel(Text("Tab placement for \(tab.title)"))
        .accessibilityValue(Text(placementTitle))
    }

    private var placementTitle: LocalizedStringKey {
        switch tab.placement {
        case .pinned: "Pinned"
        case .saved: "Saved"
        case .current: "Open"
        }
    }
}
