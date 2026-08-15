import SwiftUI

struct SidebarTabRow: View {
    let tab: BrowserTab
    let spaceID: SpaceID
    let profileID: UUID
    let isSelected: Bool
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var presentSelectedPage: () -> Void = {}
    var isLoaded = true
    var unload: ((TabID) -> Void)? = nil
    var pullNewIcon: (() -> Void)? = nil
    var restoreSavedLocation: (() -> Void)? = nil
    var promotionNamespace: Namespace.ID? = nil
    /// Set by `SidebarSplitGroupRow` for the rows it nests. See
    /// `SidebarTabRowConfiguration.isSplitGroupMember`.
    var isSplitGroupMember = false

    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var renameRequest: BrowserTabRuntimeAssignment?
    @State private var draftTitle = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        SidebarTabRowContent(
            configuration: configuration,
            interaction: interaction
        )
        .modifier(
            SidebarTabRowSurface(
                configuration: configuration,
                interaction: interaction
            )
        )
        .onChange(of: runtimeAssignment) { _, assignment in
            guard renameRequest != assignment else { return }
            cancelTitleEditing()
        }
        .onChange(of: configuration.isCurrentAndUnlocked) { _, isAvailable in
            guard !isAvailable else { return }
            cancelTitleEditing()
        }
    }

    private var configuration: SidebarTabRowConfiguration {
        SidebarTabRowConfiguration(
            tab: tab,
            spaceID: spaceID,
            profileID: profileID,
            isSelected: isSelected,
            canClose: canClose,
            browser: browser,
            spaceAccess: spaceAccess,
            presentSelectedPage: presentSelectedPage,
            isLoaded: isLoaded,
            unload: unload,
            pullNewIcon: pullNewIcon,
            restoreSavedLocation: restoreSavedLocation,
            promotionNamespace: promotionNamespace,
            isSplitGroupMember: isSplitGroupMember
        )
    }

    private var interaction: SidebarTabRowInteractionContext {
        SidebarTabRowInteractionContext(
            isHovering: $isHovering,
            isDropTargeted: $isDropTargeted,
            isRenaming: isRenaming,
            draftTitle: $draftTitle,
            isTitleFocused: $isTitleFocused,
            beginRenaming: beginRenaming,
            commitTitle: commitTitle,
            cancelTitleEditing: cancelTitleEditing,
            dismissFromMiddleClick: dismissFromMiddleClick
        )
    }

    private func beginRenaming() {
        guard configuration.isCurrentAndUnlocked else { return }
        draftTitle = tab.displayTitle
        renameRequest = runtimeAssignment
        Task { @MainActor in
            isTitleFocused = true
        }
    }

    private func commitTitle() {
        guard let request = renameRequest else { return }
        renameRequest = nil
        guard request == runtimeAssignment,
            configuration.isCurrentAndUnlocked
        else { return }
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

    private func dismissFromMiddleClick() {
        guard configuration.isCurrentAndUnlocked else { return }
        switch BrowserTabMiddleClickPolicy.action(for: tab.placement) {
        case .close:
            browser.closeTab(tab.id, matching: configuration.assignment)
        case .unload:
            guard isLoaded else { return }
            unload?(tab.id)
        }
    }

    private var isRenaming: Bool {
        renameRequest == runtimeAssignment
            && configuration.isCurrentAndUnlocked
    }

    private var runtimeAssignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tab.id,
            spaceID: spaceID,
            profileID: profileID
        )
    }
}

#Preview {
    @Previewable @Namespace var promotionNamespace
    let configuration = SidebarTabRowPreviewFixture.configuration()

    SidebarTabRow(
        tab: configuration.tab,
        spaceID: configuration.spaceID,
        profileID: configuration.profileID,
        isSelected: configuration.isSelected,
        canClose: configuration.canClose,
        browser: configuration.browser,
        spaceAccess: configuration.spaceAccess,
        promotionNamespace: promotionNamespace
    )
    .frame(width: 320)
    .padding()
}
