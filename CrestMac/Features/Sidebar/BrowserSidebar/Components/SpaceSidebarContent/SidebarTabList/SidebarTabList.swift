import SwiftUI

struct SidebarTabList: View {
    let space: BrowserSpace
    let tabSections: BrowserTabSections
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let openNewTab: () -> Void
    let isSavedTabsExpanded: Bool
    @Binding var editingFolderRequest: BrowserFolderRuntimeAssignment?
    let tabPromotionNamespace: Namespace.ID
    let editSpace: () -> Void
    let createSpace: () -> Void

    @State private var isHoveringSidebar = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 0) {
                        if isSavedTabsExpanded {
                            SavedTabsDropSection(
                                space: space,
                                tabSections: tabSections,
                                browser: browser,
                                pages: pages,
                                spaceAccess: spaceAccess,
                                editingFolderRequest: $editingFolderRequest
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        CurrentTabsDivider(
                            showsClearAction: isHoveringSidebar,
                            canClear: !tabSections.sidebarCurrentTabs.isEmpty,
                            clear: clearCurrentTabs
                        )

                        CurrentTabsDropSection(
                            space: space,
                            tabs: tabSections.sidebarCurrentTabs,
                            browser: browser,
                            pages: pages,
                            spaceAccess: spaceAccess,
                            openNewTab: openNewTab,
                            tabPromotionNamespace: tabPromotionNamespace
                        )
                    }

                    BrowserSidebarBackgroundInteractionView(
                        editSpace: editSpace,
                        createSpace: createSpace
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollClipDisabled(
                !BrowserSidebarReorderVisuals.clipsScrollableRegion(
                    clipsWhenIdle: BrowserSidebarScrollLayoutPolicy
                        .clipsScrollableRegion,
                    isDragging: browser.sidebarReorderState.isDragging
                )
            )
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                BrowserAddressFocusDismissal.dismiss()
            }
        )
        .onHover { isHoveringSidebar = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved and current tabs")
    }

    private func clearCurrentTabs() {
        let actions = BrowserSidebarTabActions(
            assignment: BrowserSpaceRuntimeAssignment(space: space),
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
        _ = actions.clearCurrentTabs()
    }
}

#Preview("Sidebar Tab List") {
    @Previewable @State var editingFolderRequest: BrowserFolderRuntimeAssignment? = nil
    @Previewable @Namespace var tabPromotionNamespace
    let browser = BrowserSidebarPreviewFixture.makeBrowser()
    SidebarTabList(
        space: BrowserSidebarPreviewFixture.space,
        tabSections: BrowserSidebarPreviewFixture.space.tabSections,
        browser: browser,
        pages: BrowserSidebarPreviewFixture.makePages(),
        spaceAccess: BrowserSidebarPreviewFixture.makeSpaceAccess(),
        openNewTab: {},
        isSavedTabsExpanded: true,
        editingFolderRequest: $editingFolderRequest,
        tabPromotionNamespace: tabPromotionNamespace,
        editSpace: {},
        createSpace: {}
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth, height: 520)
}
