import SwiftUI

struct MobileBrowserSpacePage: View {
    let space: BrowserSpace
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let mode: MobileBrowserSidebarMode
    let tabPromotionNamespace: Namespace.ID
    let selectTab: (TabID) -> Void
    let openNewTab: () -> Void
    let showHistory: () -> Void
    let showPasswords: () -> Void
    let showSettings: () -> Void
    let closePrivateBrowsing: () -> Void
    let compactPageIsFullyPresented: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editingFolderRequest: BrowserFolderRuntimeAssignment?

    @State private var reorderOrigin = CGPoint.zero

    var body: some View {
        let tabSections = space.tabSections

        VStack(spacing: 0) {
            MobilePinnedTabsDropSection(
                space: space,
                tabSections: tabSections,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                selectTab: selectTab,
                tabPromotionNamespace: tabPromotionNamespace,
                usesNativeNavigationTransition: mode == .compactTabViewer
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            MobileSpaceHeader(
                space: space,
                isPrivateBrowsing: browser.isPrivateBrowsing,
                isSavedTabsExpanded: savedTabsExpansionBinding,
                openNewTab: openNewTab,
                createFolder: beginCreatingFolder,
                showHistory: showHistory,
                showPasswords: showPasswords,
                showSettings: showSettings,
                closePrivateBrowsing: closePrivateBrowsing,
                cleanup: browser.cleanupCurrentTabs
            )

            ScrollViewReader { proxy in
                ScrollView {
                    // Keep the compact destination laid out beneath the expanded
                    // surface. Do the same for the selected tab,
                    // using an eager stack so the in-place morph always has a
                    // real resting frame instead of materializing offscreen.
                    VStack(spacing: 0) {
                        if space.isSavedTabsExpanded {
                            MobileSavedTabsDropSection(
                                space: space,
                                tabSections: tabSections,
                                browser: browser,
                                pages: pages,
                                spaceAccess: spaceAccess,
                                selectTab: selectTab,
                                editingFolderRequest: $editingFolderRequest,
                                tabPromotionNamespace: tabPromotionNamespace,
                                usesNativeNavigationTransition: mode == .compactTabViewer
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)

                        MobileCurrentTabsDropSection(
                            space: space,
                            tabs: tabSections.sidebarCurrentTabs,
                            browser: browser,
                            pages: pages,
                            spaceAccess: spaceAccess,
                            selectTab: selectTab,
                            openNewTab: openNewTab,
                            tabPromotionNamespace: tabPromotionNamespace,
                            usesNativeNavigationTransition: mode == .compactTabViewer
                        )
                    }
                    .padding(.bottom, 8)
                }
                .scrollClipDisabled(
                    !BrowserSidebarReorderVisuals.clipsScrollableRegion(
                        clipsWhenIdle: BrowserSidebarScrollLayoutPolicy
                            .clipsScrollableRegion,
                        isDragging: browser.sidebarReorderState.isDragging
                    )
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        BrowserAddressFocusDismissal.dismiss()
                    }
                )
                .accessibilityLabel("Saved and current tabs")
                .accessibilityIdentifier(
                    BrowserSpaceAccessibilityID.tabs(space.id)
                )
                .onChange(of: selectedPromotionTarget) { previous, current in
                    guard
                        MobileTabPromotionPolicy.shouldPreposition(
                            previous: previous,
                            current: current,
                            compactPageIsFullyPresented: compactPageIsFullyPresented
                        ), let current
                    else { return }

                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(current.tabID, anchor: .center)
                    }
                }
            }
        }
        // Covers the whole sidebar — pinned strip included — because the pinned
        // grid sits outside the scrolling list. A feed attached to the list alone
        // never sees the pointer over pinned, so a tab could not be dropped there.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
        } action: { frame in
            reorderOrigin = frame.origin
        }
        .onDrop(
            of: [.json],
            delegate: BrowserSidebarReorderDropDelegate(
                reorder: BrowserSidebarReorderContext(
                    browser: browser,
                    spaceAccess: spaceAccess
                ),
                origin: reorderOrigin
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            BrowserSpaceAccessibilityID.sidebar(space.id)
        )
        .accessibilityLabel("\(space.name) Space sidebar")
    }

    private var selectedTab: BrowserTab? {
        guard let selectedTabID = space.selectedTabID else { return nil }
        return space.tabs.first { $0.id == selectedTabID }
    }

    private var selectedPromotionTarget: MobileTabPromotionTarget? {
        MobileTabPromotionPolicy.target(
            for: selectedTab,
            selectedTabID: space.selectedTabID
        )
    }

    private func beginCreatingFolder() {
        guard isCurrentAndUnlocked,
            let folderID = browser.addFolder(matching: assignment)
        else { return }
        browser.setSavedTabsExpanded(true, matching: assignment)
        editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: folderID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }

    private var savedTabsExpansionBinding: Binding<Bool> {
        Binding {
            browser.space(matching: assignment)?.isSavedTabsExpanded ?? true
        } set: { isExpanded in
            guard isCurrentAndUnlocked else { return }
            browser.setSavedTabsExpanded(isExpanded, matching: assignment)
        }
    }

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }

    private var isCurrentAndUnlocked: Bool {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        ) != nil
    }
}

#Preview("Mobile Browser Space Page") {
    @Previewable @Namespace var tabPromotionNamespace
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileBrowserSpacePage(
        space: fixture.space,
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: fixture.spaceAccess,
        mode: .compactTabViewer,
        tabPromotionNamespace: tabPromotionNamespace,
        selectTab: { _ in },
        openNewTab: {},
        showHistory: {},
        showPasswords: {},
        showSettings: {},
        closePrivateBrowsing: {},
        compactPageIsFullyPresented: false
    )
    .frame(width: 390, height: 700)
}
