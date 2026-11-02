import SwiftUI

/// One Space's sidebar on the compact shell: the pinned grid, the Space header,
/// and the scrolling tab list.
///
/// Everything here is composition and binding. The sections and the list are the
/// shared ones; what this shell adds is its own scrolling chrome, the drop feed
/// that covers the whole sidebar, and the page-facing closures only a single
/// compact page can answer.
struct MobileBrowserSpacePage: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    let space: SpaceModel
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    let tabPromotionNamespace: Namespace.ID
    let selectTab: (UUID) -> Void
    let openNewTab: () -> Void
    let showHistory: () -> Void
    let showPasswords: () -> Void
    let showSettings: () -> Void
    let closePrivateBrowsing: () -> Void
    let compactPageIsFullyPresented: Bool

    @Environment(\.openWindow) private var openWindow
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        if let listContext {
            content(listContext)
        }
    }

    private func content(_ listContext: BrowserSidebarListContext) -> some View {
        let (sharesPinsBefore, sharesPinsAfter) = (sharesPins(with: -1), sharesPins(with: 1))
        let layoutDirection = layoutDirection
        return VStack(spacing: 0) {
            // The bounded pinned grid keeps its intrinsic height. Compressing
            // its wrapper when the keyboard appears lets fixed-height tiles
            // overflow upward into the Space picker.
            BrowserPinnedTabsDropSection(context: listContext)
                .equatable()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, BrowserSidebarMetrics.layerInset)
                .padding(.vertical, 10)
                // The pinned tabs a neighbouring Space shows too stay still
                // while the strip pages to it, and one of the two draws them.
                // The pager's own scroll offset moves them, with no update.
                // Frames are physical and offsets follow the layout
                // direction, so the offset is read along the reading order.
                .visualEffect { content, proxy in
                    let offset = layoutDirection.semanticHorizontalTranslation(
                        proxy.frame(in: .scrollView(axis: .horizontal)).minX)
                    let held = offset < 0 ? sharesPinsAfter : offset > 0 && sharesPinsBefore
                    return
                        content
                        .offset(x: held ? -offset : 0)
                        .opacity(held && abs(offset) > proxy.size.width / 2 ? 0 : 1)
                }

            BrowserSpaceHeader(
                space: space,
                isPrivateBrowsing: browser.isPrivateBrowsing,
                isSavedTabsExpanded: savedTabsExpansionBinding,
                capabilities: capabilities,
                actions: BrowserSpaceHeaderActions(
                    openNewTab: openNewTab,
                    openNewWindow: { openWindow(value: MobileWindowRequest()) },
                    createFolder: beginCreatingFolder,
                    showHistory: showHistory,
                    showPasswords: showPasswords,
                    closePrivateBrowsing: closePrivateBrowsing,
                    showSettings: showSettings,
                    cleanup: browser.cleanupCurrentTabs
                )
            )

            MobileBrowserSpaceTabListScroll(
                context: listContext,
                compactPageIsFullyPresented: compactPageIsFullyPresented,
                openNewTab: openNewTab
            ) {
                BrowserSidebarTabList(context: listContext, openNewTab: openNewTabIfAvailable)
                    .equatable()
            }
        }
        .modifier(
            MobileBrowserReorderDropFeed(
                browser: browser,
                spaceAccess: spaceAccess
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            BrowserSpaceAccessibilityID.sidebar(space.id)
        )
        .accessibilityLabel("\(space.settings.name) Space sidebar")
    }

    /// The Space and this window as the read model keeps them, and what the
    /// rows act through. Every section anchors its rows' pages here.
    private var listContext: BrowserSidebarListContext? {
        guard let window = browser.windowModel else { return nil }
        return BrowserSidebarListContext(
            space: space, window: window, favicons: browser.core.state.favicons, browser: browser,
            spaceAccess: spaceAccess, pageAccess: pageAccess, tabActions: tabActions, capabilities: capabilities,
            promotionNamespaces: [
                .pinned: tabPromotionNamespace, .saved: tabPromotionNamespace, .current: tabPromotionNamespace,
            ],
            select: selectTab, restoreSavedLocation: restoreSavedLocation)
    }

    /// Whether the Space `offset` places along the strip shows the same
    /// pinned tabs as this one, its group sharing them.
    private func sharesPins(with offset: Int) -> Bool {
        let spaces = browser.availableSpaces
        guard let index = spaces.firstIndex(where: { $0.id == space.id }), spaces.indices.contains(index + offset)
        else { return false }
        return spaces[index + offset].pinSource.id == space.pinSource.id
    }

    private var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(pages: pages, browser: browser, spaceAccess: spaceAccess)
    }

    private var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: assignment,
            browser: browser, reorderState: sidebarInteraction.sidebarReorderState,
            pages: pages,
            spaceAccess: spaceAccess
        )
    }

    private func openNewTabIfAvailable() {
        guard isCurrentAndUnlocked else { return }
        openNewTab()
    }

    private func restoreSavedLocation(_ tabID: UUID) {
        guard isCurrentAndUnlocked else { return }
        MobileSavedLocationRestoreAction(
            browser: browser,
            pages: pages,
            selectTab: selectTab,
            spaceAccess: spaceAccess
        ).perform(
            BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: space.id,
                profileID: space.profileID
            )
        )
    }

    private func beginCreatingFolder() {
        guard isCurrentAndUnlocked,
            let folderID = browser.addFolder(matching: assignment)
        else { return }
        browser.setSavedTabsExpanded(true, matching: assignment)
        sidebarInteraction.editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: folderID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }

    private var savedTabsExpansionBinding: Binding<Bool> {
        Binding {
            browser.spaceModel(matching: assignment)?.settings.isSavedTabsExpanded ?? true
        } set: { isExpanded in
            guard isCurrentAndUnlocked else { return }
            browser.setSavedTabsExpanded(isExpanded, matching: assignment)
        }
    }

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }

    private var isCurrentAndUnlocked: Bool {
        browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil
    }
}
