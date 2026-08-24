import SwiftUI

/// A split group as one sidebar row, on every shell: a grouped surface holding
/// the count affordance and one ordinary tab row per member.
///
/// The members are not a compact imitation of a tab row — they are
/// `BrowserSidebarTabRow`, the same view the rest of the list draws, so a split
/// reads as tabs that have been gathered rather than as a widget that replaced
/// them. The container carries what belongs to the group — presented, dragged,
/// dropped against, and the two ways a split ends — and each row carries what
/// belongs to its own tab. That division is what lets a group be one row to the
/// list while still letting a person focus, rename, unload, or close one pane.
///
/// What differs between a pointer shell and a touch one is read from
/// `BrowserSidebarInteractionPolicy` rather than from which target compiled the
/// file, so the two shells share this row instead of a resemblance.
struct BrowserSidebarSplitGroupRow: View {
    let groupID: SplitGroupID
    let members: [BrowserTab]
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    var isLoaded: (TabID) -> Bool = { _ in true }
    var unload: ((TabID) -> Void)? = nil
    var pullNewIcon: ((TabID) -> Void)? = nil
    var restoreSavedLocation: ((TabID) -> Void)? = nil
    var promotionNamespace: Namespace.ID? = nil
    /// The row a drop below this group would land in front of, skipping past
    /// the whole run. Only read where the shell draws its insertion line on the
    /// rows themselves.
    var followingTabID: TabID? = nil
    var hasVisibleFollowingRow = false
    /// What opening a member means to the host, matching the tab row: the group
    /// decides *whether* and *which*, the host decides what appears.
    let select: (TabID) -> Void

    @State private var renameRequest: BrowserSplitGroupRuntimeAssignment?
    @State private var iconRequest: BrowserSplitGroupRuntimeAssignment?
    @State private var tintRequest: BrowserSplitGroupRuntimeAssignment?
    @State private var draftTitle = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        BrowserSidebarSplitGroupRowContent(
            configuration: configuration,
            interaction: interaction
        )
        .modifier(
            BrowserSidebarSplitGroupRowSurface(
                configuration: configuration,
                interaction: interaction
            )
        )
        .popover(isPresented: tintPresentation, arrowEdge: .trailing) {
            BrowserFolderColorPicker(
                color: interaction.tint,
                title: "Split View Color",
                showsReset: configuration.metadata.tint != nil,
                resetTitle: "Use Default Color",
                reset: interaction.resetTint
            )
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: configuration.runtimeAssignment) { _, assignment in
            guard renameRequest != assignment else { return }
            clearDeferredActions()
        }
        .onChange(of: configuration.isCurrentAndUnlocked) { _, available in
            guard !available else { return }
            clearDeferredActions()
        }
    }

    private var configuration: BrowserSidebarSplitGroupRowConfiguration {
        BrowserSidebarSplitGroupRowConfiguration(
            groupID: groupID,
            members: members,
            spaceID: spaceID,
            profileID: profileID,
            selectedTabID: selectedTabID,
            canClose: canClose,
            browser: browser,
            spaceAccess: spaceAccess,
            capabilities: capabilities,
            isLoaded: isLoaded,
            unload: unload,
            pullNewIcon: pullNewIcon,
            restoreSavedLocation: restoreSavedLocation,
            promotionNamespace: promotionNamespace,
            followingTabID: followingTabID,
            hasVisibleFollowingRow: hasVisibleFollowingRow,
            select: select
        )
    }

    private var interaction: BrowserSidebarSplitGroupRowInteractionContext {
        BrowserSidebarSplitGroupRowInteractionContext(
            isRenaming: isRenaming,
            draftTitle: $draftTitle,
            isTitleFocused: $isTitleFocused,
            isChoosingIcon: iconPresentation,
            isChoosingTint: tintPresentation,
            tint: tintBinding,
            activate: activate,
            beginRenaming: beginRenaming,
            beginChangingIcon: beginChangingIcon,
            beginChangingTint: beginChangingTint,
            setEmojiIcon: setRequestedEmoji,
            resetIcon: clearRequestedIcon,
            commitTitle: commitTitle,
            cancelTitleEditing: cancelTitleEditing,
            resetTint: resetTint
        )
    }

    private var isRenaming: Bool {
        renameRequest == configuration.runtimeAssignment
            && configuration.isCurrentAndUnlocked
    }

    private func activate() {
        guard configuration.isCurrentAndUnlocked,
            let memberID = configuration.focusedMemberID
                ?? configuration.members.first?.id
        else { return }
        configuration.select(memberID)
    }

    private func beginRenaming() {
        guard configuration.isCurrentAndUnlocked else { return }
        draftTitle = configuration.metadata.displayTitle
        renameRequest = configuration.runtimeAssignment
        Task { @MainActor in isTitleFocused = true }
    }

    private func commitTitle() {
        guard let request = renameRequest,
            request == configuration.runtimeAssignment,
            configuration.isCurrentAndUnlocked
        else { return }
        renameRequest = nil
        configuration.browser.setSplitGroupTitle(
            draftTitle,
            groupID: request.groupID,
            matching: request.spaceAssignment
        )
    }

    private func cancelTitleEditing() {
        draftTitle = configuration.metadata.displayTitle
        renameRequest = nil
        isTitleFocused = false
    }

    private func beginChangingIcon() {
        guard configuration.isCurrentAndUnlocked else { return }
        iconRequest = configuration.runtimeAssignment
    }

    private func beginChangingTint() {
        guard configuration.isCurrentAndUnlocked else { return }
        tintRequest = configuration.runtimeAssignment
    }

    private var iconPresentation: Binding<Bool> {
        deferredPresentation(request: $iconRequest, begin: beginChangingIcon)
    }

    private var tintPresentation: Binding<Bool> {
        deferredPresentation(request: $tintRequest, begin: beginChangingTint)
    }

    private func deferredPresentation(
        request: Binding<BrowserSplitGroupRuntimeAssignment?>,
        begin: @escaping () -> Void
    ) -> Binding<Bool> {
        Binding {
            request.wrappedValue == configuration.runtimeAssignment
                && configuration.isCurrentAndUnlocked
        } set: { isPresented in
            if isPresented {
                begin()
            } else {
                request.wrappedValue = nil
            }
        }
    }

    private var tintBinding: Binding<BrowserSpaceBrandColor> {
        Binding {
            configuration.metadata.tint ?? .folderDefault
        } set: { tint in
            guard tintRequest == configuration.runtimeAssignment,
                configuration.isCurrentAndUnlocked
            else { return }
            configuration.browser.setSplitGroupTint(
                tint,
                groupID: configuration.groupID,
                matching: configuration.assignment
            )
        }
    }

    private func resetTint() {
        guard tintRequest == configuration.runtimeAssignment,
            configuration.isCurrentAndUnlocked
        else { return }
        configuration.browser.setSplitGroupTint(
            nil,
            groupID: configuration.groupID,
            matching: configuration.assignment
        )
    }

    private func setRequestedEmoji(_ emoji: String) {
        guard iconRequest == configuration.runtimeAssignment,
            configuration.isCurrentAndUnlocked
        else { return }
        configuration.browser.setSplitGroupEmojiIcon(
            emoji,
            groupID: configuration.groupID,
            matching: configuration.assignment
        )
    }

    private func clearRequestedIcon() {
        guard iconRequest == configuration.runtimeAssignment,
            configuration.isCurrentAndUnlocked
        else { return }
        configuration.browser.setSplitGroupEmojiIcon(
            nil,
            groupID: configuration.groupID,
            matching: configuration.assignment
        )
        iconRequest = nil
    }

    private func clearDeferredActions() {
        cancelTitleEditing()
        iconRequest = nil
        tintRequest = nil
    }
}
