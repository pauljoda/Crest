import SwiftUI

struct DesktopSpaceSelectionControl: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let selectSpace: (SpaceID) -> Void

    var body: some View {
        CrestSpaceIconPicker(
            spaces: spaces,
            selectedSpaceID: selectedSpaceID,
            selectSpace: selectSpace,
            accessibilityIdentifier: "space-switcher-picker"
        ) { space in
            SpacePickerSegment(
                space: space,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                selectSpace: selectSpace
            )
        }
    }
}

#Preview("Desktop Space Selection") {
    let preview = SpaceSwitcherPreviewFixture.makeContext()
    DesktopSpaceSelectionControl(
        spaces: preview.browser.session.spaces,
        selectedSpaceID: preview.browser.session.selectedSpaceID,
        browser: preview.browser,
        pages: preview.pages,
        spaceAccess: preview.spaceAccess,
        selectSpace: { _ in }
    )
    .padding()
}
