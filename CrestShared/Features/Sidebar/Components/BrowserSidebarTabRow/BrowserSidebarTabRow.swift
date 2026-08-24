import SwiftUI

/// One tab in the sidebar, on every shell.
///
/// The row owns the state a tab row has to keep between events — hover, the
/// rename in flight, the height a drop indicator sizes itself against — and
/// hands everything else to `BrowserSidebarTabRowConfiguration`. What differs
/// between a pointer shell and a touch one is read from
/// `BrowserSidebarInteractionPolicy` rather than from which target compiled
/// the file, so the two shells share this row instead of a resemblance.
struct BrowserSidebarTabRow: View {
    let tab: BrowserTab
    let spaceID: SpaceID
    let profileID: UUID
    let isSelected: Bool
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    var isLoaded = true
    var unload: ((TabID) -> Void)? = nil
    var pullNewIcon: (() -> Void)? = nil
    var restoreSavedLocation: (() -> Void)? = nil
    var promotionNamespace: Namespace.ID? = nil
    /// Set by the container that nests this row inside a split group. See
    /// `BrowserSidebarTabRowConfiguration.isSplitGroupMember`.
    var isSplitGroupMember = false
    /// Whether the row may be lifted out of the list on its own. A split
    /// group's members hand this off to the container that drags the whole run.
    var isReorderSource = true
    /// The row a drop below this one would land in front of. Only read where
    /// the shell draws its insertion line on the rows themselves.
    var followingTabID: TabID? = nil
    var hasVisibleFollowingRow = false
    /// What opening this tab means to the host. The row decides *whether* the
    /// tab opens; the host decides what appears when it does.
    let select: (TabID) -> Void

    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var dropTargetHeight = CrestLayout.sidebarRowHeight
    @State private var renameRequest: BrowserTabRuntimeAssignment?
    @State private var iconRequest: BrowserTabRuntimeAssignment?
    @State private var draftTitle = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        BrowserSidebarTabRowContent(
            configuration: configuration,
            interaction: interaction
        )
        .modifier(
            BrowserSidebarTabRowSurface(
                configuration: configuration,
                interaction: interaction
            )
        )
        .onChange(of: runtimeAssignment) { _, assignment in
            guard renameRequest != assignment else { return }
            cancelTitleEditing()
            iconRequest = nil
        }
        .onChange(of: configuration.isCurrentAndUnlocked) { _, isAvailable in
            guard !isAvailable else { return }
            cancelTitleEditing()
            iconRequest = nil
        }
    }

    private var configuration: BrowserSidebarTabRowConfiguration {
        BrowserSidebarTabRowConfiguration(
            tab: tab,
            spaceID: spaceID,
            profileID: profileID,
            isSelected: isSelected,
            canClose: canClose,
            browser: browser,
            spaceAccess: spaceAccess,
            capabilities: capabilities,
            isLoaded: isLoaded,
            unload: unload,
            pullNewIcon: pullNewIcon,
            restoreSavedLocation: restoreSavedLocation,
            promotionNamespace: promotionNamespace,
            isSplitGroupMember: isSplitGroupMember,
            isReorderSource: isReorderSource,
            followingTabID: followingTabID,
            hasVisibleFollowingRow: hasVisibleFollowingRow,
            select: select
        )
    }

    private var interaction: BrowserSidebarTabRowInteractionContext {
        BrowserSidebarTabRowInteractionContext(
            isHovering: $isHovering,
            isDropTargeted: $isDropTargeted,
            dropTargetHeight: $dropTargetHeight,
            isRenaming: isRenaming,
            draftTitle: $draftTitle,
            isTitleFocused: $isTitleFocused,
            isChoosingIcon: iconPresentation,
            activate: activate,
            beginRenaming: beginRenaming,
            beginChangingIcon: beginChangingIcon,
            setEmojiIcon: setRequestedTabEmoji,
            resetIcon: clearRequestedTabIcon,
            commitTitle: commitTitle,
            cancelTitleEditing: cancelTitleEditing,
            dismissFromAuxiliaryClick: dismissFromAuxiliaryClick
        )
    }

    private func activate() {
        guard configuration.isCurrentAndUnlocked else { return }
        // The lift and this button recognise simultaneously — deliberately, or
        // the button would suppress the lift — so the release that ends a
        // reorder also arrives here. Reject it rather than opening the tab that
        // was just moved.
        guard !browser.sidebarReorderState.suppressesActivation else { return }
        select(tab.id)
    }

    private func beginRenaming() {
        guard configuration.isCurrentAndUnlocked else { return }
        draftTitle = tab.displayTitle
        renameRequest = runtimeAssignment
        Task { @MainActor in
            isTitleFocused = true
        }
    }

    private func beginChangingIcon() {
        guard configuration.isCurrentAndUnlocked else { return }
        iconRequest = runtimeAssignment
    }

    private var iconPresentation: Binding<Bool> {
        Binding {
            iconRequest == runtimeAssignment
                && configuration.isCurrentAndUnlocked
        } set: { isPresented in
            if isPresented {
                beginChangingIcon()
            } else {
                iconRequest = nil
            }
        }
    }

    private func setRequestedTabEmoji(_ emoji: String) {
        guard let request = iconRequest,
            request == runtimeAssignment,
            configuration.isCurrentAndUnlocked
        else { return }
        browser.setTabEmojiIcon(
            emoji,
            for: request.tabID,
            matching: configuration.assignment
        )
    }

    private func clearRequestedTabIcon() {
        guard let request = iconRequest,
            request == runtimeAssignment,
            configuration.isCurrentAndUnlocked
        else { return }
        browser.clearTabIcon(
            for: request.tabID,
            matching: configuration.assignment
        )
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

    private func dismissFromAuxiliaryClick() {
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
    let configuration = BrowserSidebarTabRowPreviewFixture.configuration()

    BrowserSidebarTabRow(
        tab: configuration.tab,
        spaceID: configuration.spaceID,
        profileID: configuration.profileID,
        isSelected: configuration.isSelected,
        canClose: configuration.canClose,
        browser: configuration.browser,
        spaceAccess: configuration.spaceAccess,
        capabilities: configuration.capabilities,
        promotionNamespace: promotionNamespace,
        select: { _ in }
    )
    .frame(width: 320)
    .padding()
}
