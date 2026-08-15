import SwiftUI

struct BrowserTabEditActions: View {
    let tab: BrowserTab
    let isLoaded: Bool
    let pullNewIcon: (() -> Void)?
    let restoreSavedLocation: (() -> Void)?
    let performIfCurrent: ((BrowserTab) -> Void) -> Void
    let replaceSavedLocation: (BrowserTab) -> Void
    let clearIcon: (BrowserTab) -> Void
    let setEmoji: (BrowserTab, String) -> Void

    var body: some View {
        if tab.supportsSavedLocationEditing {
            Menu("Edit Tab", systemImage: "pencil") {
                Button(
                    "Replace with Current URL",
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    performIfCurrent(replaceSavedLocation)
                }
                .disabled(!tab.isAwayFromSavedLocation)

                Button("Return to Saved URL", systemImage: "arrow.uturn.backward") {
                    performIfCurrent { _ in restoreSavedLocation?() }
                }
                .disabled(
                    !tab.isAwayFromSavedLocation
                        || restoreSavedLocation == nil
                )

                Divider()
                BrowserTabIconActions(
                    tab: tab,
                    isLoaded: isLoaded,
                    pullNewIcon: pullNewIcon,
                    performIfCurrent: performIfCurrent,
                    clearIcon: clearIcon,
                    setEmoji: setEmoji
                )
            }
        } else {
            BrowserTabIconActions(
                tab: tab,
                isLoaded: isLoaded,
                pullNewIcon: pullNewIcon,
                performIfCurrent: performIfCurrent,
                clearIcon: clearIcon,
                setEmoji: setEmoji
            )
        }
    }
}

#Preview("Tab Edit Actions", traits: .sizeThatFitsLayout) {
    let fixture = BrowserSidebarInteractionPreviewFixture()

    Menu("Open Edit Actions", systemImage: "pencil") {
        BrowserTabEditActions(
            tab: fixture.savedTab,
            isLoaded: true,
            pullNewIcon: {},
            restoreSavedLocation: {},
            performIfCurrent: { action in action(fixture.savedTab) },
            replaceSavedLocation: { _ in },
            clearIcon: { _ in },
            setEmoji: { _, _ in }
        )
    }
    .padding()
}
