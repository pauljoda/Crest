import SwiftUI

struct BrowserRootSelectionObserver: ViewModifier {
    let selectedTabID: TabID?
    let selectedSpaceID: SpaceID
    let selectedSpaceIsLocked: Bool
    let tabSelectionChanged: () -> Void
    let spaceSelectionChanged: () -> Void
    let lockChanged: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: selection) { previous, current in
                if previous.spaceID != current.spaceID {
                    spaceSelectionChanged()
                } else if previous.tabID != current.tabID {
                    tabSelectionChanged()
                }
            }
            .onChange(of: selectedSpaceIsLocked) {
                lockChanged()
            }
    }

    private var selection: BrowserRootSelectionSnapshot {
        BrowserRootSelectionSnapshot(
            tabID: selectedTabID,
            spaceID: selectedSpaceID
        )
    }
}

#Preview("Browser Root Selection Observer") {
    Text("Browser")
        .modifier(
            BrowserRootSelectionObserver(
                selectedTabID: BrowserRootPreviewFixture.startTabID,
                selectedSpaceID: BrowserRootPreviewFixture.spaceID,
                selectedSpaceIsLocked: false,
                tabSelectionChanged: {},
                spaceSelectionChanged: {},
                lockChanged: {}
            )
        )
}
