import SwiftUI

struct SpaceSwitcher: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let selectSpace: (SpaceID) -> Void
    let commonListsAreExpanded: Bool
    let toggleCommonLists: () -> Void
    let recordCommonListsTriggerFrame: (CGRect) -> Void

    var body: some View {
        SpaceSwitcherContent(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            selectSpace: selectSpace,
            commonListsAreExpanded: commonListsAreExpanded,
            toggleCommonLists: toggleCommonLists,
            recordCommonListsTriggerFrame: recordCommonListsTriggerFrame
        )
        .padding(.horizontal, 12)
        .frame(height: 50)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }
}

#Preview("Space Switcher") {
    let preview = SpaceSwitcherPreviewFixture.makeContext()
    SpaceSwitcher(
        browser: preview.browser,
        pages: preview.pages,
        spaceAccess: preview.spaceAccess,
        selectSpace: { _ in },
        commonListsAreExpanded: false,
        toggleCommonLists: {},
        recordCommonListsTriggerFrame: { _ in }
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
}
