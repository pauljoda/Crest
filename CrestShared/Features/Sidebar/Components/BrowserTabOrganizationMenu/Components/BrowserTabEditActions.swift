import SwiftUI

struct BrowserTabEditActions: View {
    let tab: BrowserTab
    let isLoaded: Bool
    let pullNewIcon: (() -> Void)?
    let restoreSavedLocation: (() -> Void)?
    let performIfCurrent: ((BrowserTab) -> Void) -> Void
    let replaceSavedLocation: (BrowserTab) -> Void
    let clearIcon: (BrowserTab) -> Void
    let changeIcon: (BrowserTab) -> Void

    var body: some View {
        if tab.supportsSavedLocationEditing {
            Menu("Edit Tab", systemImage: "pencil") {
                Group {
                    Button(
                        "Replace with Current URL",
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        performIfCurrent(replaceSavedLocation)
                    }
                    .disabled(!tab.isAwayFromSavedLocation)

                    Button(
                        "Return to Saved URL",
                        systemImage: "arrow.uturn.backward"
                    ) {
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
                        changeIcon: changeIcon
                    )
                }
                .crestMenuActionLabelStyle()
            }
        } else {
            BrowserTabIconActions(
                tab: tab,
                isLoaded: isLoaded,
                pullNewIcon: pullNewIcon,
                performIfCurrent: performIfCurrent,
                clearIcon: clearIcon,
                changeIcon: changeIcon
            )
        }
    }
}
