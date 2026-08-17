import SwiftUI

struct SpaceSwitcherContent: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let selectSpace: (SpaceID) -> Void
    let commonListsAreExpanded: Bool
    let toggleCommonLists: () -> Void
    let recordCommonListsTriggerFrame: (CGRect) -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                Spacer()
                SpaceSwitcherCommonListsButton(
                    isExpanded: commonListsAreExpanded,
                    action: toggleCommonLists,
                    recordFrame: recordCommonListsTriggerFrame
                )
            }
            DesktopSpaceSelectionControl(
                spaces: BrowserSidebarAccessPolicy.availableSpaces(in: browser),
                selectedSpaceID: browser.session.selectedSpaceID,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                selectSpace: selectSpace
            )
        }
    }
}
