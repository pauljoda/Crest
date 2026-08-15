import SwiftUI

struct BrowserSourceImportTabPlacementMenu: View {
    let tab: BrowserTab
    let setPlacement: (TabID, TabPlacement) -> Void

    var body: some View {
        Menu {
            Button("Pinned", systemImage: "pin.fill") {
                setPlacement(tab.id, .pinned)
            }
            Button("Saved", systemImage: "bookmark.fill") {
                setPlacement(tab.id, .saved)
            }
            Button("Open", systemImage: "rectangle") {
                setPlacement(tab.id, .current)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 22, height: 22)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
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

#Preview("Source Import Placement Menu") {
    BrowserSourceImportTabPlacementMenu(
        tab: BrowserImportPreviewFixture.savedTab,
        setPlacement: { _, _ in }
    )
    .padding()
}
