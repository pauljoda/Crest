import SwiftUI
import UniformTypeIdentifiers

struct MobileSidebarTabRow: View {
    let tab: BrowserTab
    let followingTabID: TabID?
    let hasVisibleFollowingRow: Bool
    let spaceID: SpaceID
    let profileID: UUID
    let isSelected: Bool
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var isLoaded = true
    var unload: ((TabID) -> Void)? = nil
    var pullNewIcon: (() -> Void)? = nil
    var restoreSavedLocation: (() -> Void)? = nil
    var promotionNamespace: Namespace.ID? = nil
    var usesNativeNavigationTransition = false
    let select: (TabID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isDropTargeted = false
    @State private var dropTargetHeight = CrestLayout.sidebarRowHeight
    @State private var isHovering = false
    @State private var renameRequest: BrowserTabRuntimeAssignment?
    @State private var draftTitle = ""
    @FocusState private var isTitleFocused: Bool

    private var beforeDropLocation: BrowserTabDropLocation {
        .init(
            placement: tab.placement,
            folderID: tab.folderID,
            beforeTabID: tab.id,
            destinationAssignment: assignment
        )
    }

    private var afterDropLocation: BrowserTabDropLocation {
        .init(
            placement: tab.placement,
            folderID: tab.folderID,
            beforeTabID: followingTabID,
            destinationAssignment: assignment
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            if isRenaming {
                titleField
            } else {
                MobileSidebarTabActivationButton(
                    tab: tab,
                    profileID: profileID,
                    isSelected: isSelected,
                    isLoaded: isLoaded,
                    restoreSavedLocation: restoreSavedLocation,
                    select: activate
                )
            }

            if tab.placement == .saved, let unload {
                Button("Unload \(tab.displayTitle)", systemImage: "minus") {
                    guard isCurrentAndUnlocked else { return }
                    unload(tab.id)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 44, height: 44)
                .opacity(isLoaded ? 1 : 0)
                .disabled(!isLoaded)
            } else if canClose {
                Button("Close \(tab.displayTitle)", systemImage: "xmark") {
                    guard isCurrentAndUnlocked else { return }
                    browser.closeTab(tab.id, matching: assignment)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(BrowserVisualAccessibilityPolicy.tabCloseForeground)
                .opacity(isSelected ? 1 : 0.65)
            }
        }
        .padding(
            .leading,
            MobileSidebarRowLayoutPolicy.rootContentLeadingInset
        )
        .padding(.trailing, 4)
        .frame(
            minHeight: dynamicTypeSize.isAccessibilitySize
                ? 56
                : CrestLayout.sidebarRowHeight
        )
        .crestInteractiveSurface(
            isSelected: isSelected,
            isHovering: isHovering,
            cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
        .mobileTabTransitionSource(
            id: MobileTabPromotionPolicy.destinationID(for: tab.id),
            in: promotionNamespace,
            usesNativeNavigationTransition: usesNativeNavigationTransition,
            isEnabled: MobileTabPromotionPolicy.isTransitionSource(
                tab,
                selectedTabID: isSelected ? tab.id : nil
            )
        )
        .padding(.horizontal, 8)
        .onHover { isHovering = $0 }
        .browserTabDraggable(
            tab: tab,
            profileID: profileID,
            spaceID: spaceID,
            dragState: browser.tabDragState,
            reorder: BrowserSidebarReorderContext(
                browser: browser,
                spaceAccess: spaceAccess
            ),
            isEnabled: !isRenaming && isCurrentAndUnlocked
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            dropTargetHeight = newHeight
        }
        .overlay(alignment: .top) {
            BrowserTabDropIndicator(
                location: beforeDropLocation,
                dragState: browser.tabDragState,
                isTargeted: isDropTargeted
            )
        }
        .overlay(alignment: .bottom) {
            if BrowserTabRowIndicatorOwnershipPolicy.showsAfterRowIndicator(
                hasVisibleFollowingRow: hasVisibleFollowingRow
            ) {
                BrowserTabDropIndicator(
                    location: afterDropLocation,
                    dragState: browser.tabDragState,
                    isTargeted: isDropTargeted
                )
            }
        }
        .crestCollectionItemTransition()
        .accessibilityElement(children: .contain)
        .contextMenu {
            BrowserTabOrganizationMenu(
                tab: tab,
                assignment: runtimeAssignment,
                browser: browser,
                spaceAccess: spaceAccess,
                isLoaded: isLoaded,
                unload: unload,
                pullNewIcon: pullNewIcon,
                restoreSavedLocation: restoreSavedLocation,
                renameTab: beginRenaming
            )
            .tint(.primary)
            .onAppear {
                browser.tabDragState.contextMenuDidOpen(for: runtimeAssignment)
            }
            .onDisappear {
                browser.tabDragState.contextMenuDidClose(for: runtimeAssignment)
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused, isRenaming {
                commitTitle()
            }
        }
        .onChange(of: runtimeAssignment) { _, assignment in
            guard renameRequest != assignment else { return }
            cancelTitleEditing()
        }
        .onChange(of: isCurrentAndUnlocked) { _, isAvailable in
            guard !isAvailable else { return }
            cancelTitleEditing()
        }
    }

    private func activate() {
        guard isCurrentAndUnlocked else { return }
        // The lift and this button recognise simultaneously — deliberately, or the
        // button would suppress the lift — so the touch-up that ends a drag also
        // arrives here. Reject it rather than opening the tab that was just moved.
        guard !browser.sidebarReorderState.suppressesActivation else { return }
        select(tab.id)
    }

    /// Renaming edits the name in place, the way a mobile folder row does, so
    /// Done commits and an empty commit hands the tab back to its page title.
    private var titleField: some View {
        Label {
            TextField("Tab Name", text: $draftTitle)
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit(commitTitle)
                .accessibilityIdentifier("tab-rename-field")
        } icon: {
            TabFaviconView(tab: tab, profileID: profileID, size: 18)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 20)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func beginRenaming() {
        guard isCurrentAndUnlocked else { return }
        draftTitle = tab.displayTitle
        renameRequest = runtimeAssignment
        Task { @MainActor in
            isTitleFocused = true
        }
    }

    private func commitTitle() {
        guard let request = renameRequest else { return }
        renameRequest = nil
        guard request == runtimeAssignment, isCurrentAndUnlocked else { return }
        browser.setTabCustomTitle(
            draftTitle,
            for: request.tabID,
            matching: BrowserSpaceRuntimeAssignment(
                spaceID: request.spaceID,
                profileID: request.profileID
            )
        )
    }

    private func cancelTitleEditing() {
        guard renameRequest != nil else { return }
        draftTitle = tab.displayTitle
        renameRequest = nil
    }

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }

    private var runtimeAssignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tab.id,
            spaceID: spaceID,
            profileID: profileID
        )
    }

    private var isRenaming: Bool {
        renameRequest == runtimeAssignment && isCurrentAndUnlocked
    }

    private var isCurrentAndUnlocked: Bool {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        return space.tabs.contains(where: { $0.id == tab.id })
    }
}

#Preview("Mobile Sidebar Tab Row", traits: .sizeThatFitsLayout) {
    @Previewable @Namespace var promotionNamespace
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileSidebarTabRow(
        tab: fixture.currentTab,
        followingTabID: nil,
        hasVisibleFollowingRow: false,
        spaceID: fixture.space.id,
        profileID: fixture.space.profile.id,
        isSelected: true,
        canClose: true,
        browser: fixture.browser,
        spaceAccess: fixture.spaceAccess,
        isLoaded: true,
        promotionNamespace: promotionNamespace,
        usesNativeNavigationTransition: false,
        select: { _ in }
    )
    .frame(width: 360)
}
