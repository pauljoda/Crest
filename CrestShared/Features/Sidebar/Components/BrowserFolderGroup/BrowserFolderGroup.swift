import SwiftUI

/// One folder in the sidebar — its header and the rows it holds — on every
/// shell.
///
/// The group owns the state a folder has to keep between events: which
/// deferred action a menu asked for, and which tab a collapsed folder is still
/// showing. Everything a part needs to draw arrives as
/// `BrowserFolderGroupConfiguration`; everything a part may do arrives as
/// `BrowserFolderGroupInteractionContext`. What the folder holds is the list
/// the core publishes for its inside, drawn only while the folder is open, so
/// a collapse redraws this group alone.
///
/// A folder's menu actions outlive the menu that asked for them, so each is
/// held as the folder it was asked for rather than as a bare flag, and every
/// one of them is re-checked against the live Space before it runs. A Space
/// can be reselected, relocked, or have the folder deleted out from under an
/// open colour popover, and a request that can no longer be honoured is
/// dropped instead of landing on whatever took its place.
struct BrowserFolderGroup: View {
    // MARK: - Variables

    @Environment(BrowserSidebarInteractionState.self) var sidebarInteraction

    let folder: FolderStateModel
    /// How many folders hold this one.
    let depth: Int
    let context: BrowserSidebarListContext
    /// The tab a collapsed folder around this one keeps on screen, which this
    /// folder shows in place of its contents.
    var inheritedKeptTabID: UUID? = nil

    @Environment(\.sidebarSpacePresentation) var spacePresentation
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var draftTitle = ""
    @State var iconRequest: BrowserFolderRuntimeAssignment?
    @State var colorRequest: BrowserFolderRuntimeAssignment?
    @State var deletionRequest: BrowserFolderRuntimeAssignment?
    #if os(macOS)
        var collapsedTabVisibility: BrowserCollapsedFolderTabVisibilityState {
            get { collapsedVisibilityOwner.state }
            nonmutating set { collapsedVisibilityOwner.state = newValue }
        }

        var collapsedVisibilityOwner: BrowserSidebarFolderVisibility {
            sidebarInteraction.collapsedFolderVisibility(
                for: BrowserFolderRuntimeAssignment(
                    folderID: folder.id, spaceID: context.space.id, profileID: context.space.profileID))
        }
    #else
        @State var collapsedTabVisibility = BrowserCollapsedFolderTabVisibilityState()
    #endif
    @FocusState var isTitleFocused: Bool

    var configuration: BrowserFolderGroupConfiguration {
        BrowserFolderGroupConfiguration(
            sidebarInteraction: sidebarInteraction, folder: folder, depth: depth, context: context,
            spacePresentation: spacePresentation, inheritedKeptTabID: inheritedKeptTabID)
    }

    var isExpanded: Binding<Bool> {
        Binding {
            !folder.isCollapsed
        } set: { isExpanded in
            guard configuration.isCurrentAndUnlocked else { return }
            context.browser.setFolderCollapsed(
                folder.id, matching: configuration.assignment, isCollapsed: !isExpanded)
        }
    }

    var editingFolderRequest: Binding<BrowserFolderRuntimeAssignment?> {
        Binding {
            sidebarInteraction.editingFolderRequest
        } set: {
            sidebarInteraction.editingFolderRequest = $0
        }
    }

    var interaction: BrowserFolderGroupInteractionContext {
        BrowserFolderGroupInteractionContext(
            isExpanded: isExpanded,
            editingFolderRequest: editingFolderRequest,
            draftTitle: $draftTitle,
            isChoosingColor: colorPresentation,
            isChoosingIcon: iconPresentation,
            folderSymbol: folderSymbolBinding,
            isConfirmingDeletion: deletionPresentation,
            collapsedTabVisibility: Binding(
                get: { collapsedTabVisibility }, set: { collapsedTabVisibility = $0 }),
            isTitleFocused: $isTitleFocused,
            folderColor: folderColorBinding,
            beginCreatingChild: beginCreatingChild,
            beginRenaming: beginRenaming,
            toggleExpansion: toggleExpansion,
            beginTitleEditingIfNeeded: beginTitleEditingIfNeeded,
            commitTitle: commitTitle,
            cancelTitleEditing: cancelTitleEditing,
            deleteFolder: deleteFolder,
            unloadKeptCollapsedTab: unloadKeptCollapsedTab
        )
    }

    var body: some View {
        let configuration = self.configuration
        let interaction = self.interaction
        let showsContents = configuration.showsContents
        VStack(spacing: 0) {
            BrowserFolderGroupSurface(configuration: configuration, interaction: interaction)
            if showsContents {
                folderContents(configuration: configuration)
            }
        }
        .environment(\.browserInteractionCapabilities, context.capabilities)
        .modifier(
            BrowserFolderSectionSurface(
                color: folder.displayColor,
                intensity: configuration.displayBranding?.folderColorIntensity ?? 0,
                textColorMode: configuration.displayBranding?.textColorMode ?? .automatic,
                depth: depth, isExpanded: showsContents,
                isSelected: BrowserSidebarSelection.showsSelected(.folder(folder.id), in: context),
                folderID: folder.id, reorder: sidebarInteraction.sidebarReorderState)
        )
        .modifier(BrowserFolderReorderContainer(configuration: configuration))
        .browserSidebarReorderZone(
            .section(.tabs(placement: folder.location, folderID: folder.id)),
            state: sidebarInteraction.sidebarReorderState
        )
        .browserSidebarReorderZone(
            .folder(folder.id),
            state: sidebarInteraction.sidebarReorderState,
            isActive: !showsContents
        )
        .modifier(
            BrowserFolderReorderReservation(configuration: configuration)
        )
        .onChange(of: configuration.folderRuntimeAssignment) { _, _ in
            clearUnavailableDeferredActions()
        }
        .modifier(
            SidebarSpaceRoleCleanupModifier(
                isAvailable: configuration.isAvailableForDisplay,
                hasPendingActions: sidebarInteraction.editingFolderRequest == configuration.folderRuntimeAssignment
                    || colorRequest != nil || iconRequest != nil || deletionRequest != nil,
                cancel: clearUnavailableDeferredActions
            )
        )
        .padding(.vertical, BrowserSidebarMetrics.containerSpacing)
    }

}

extension BrowserFolderGroup: @MainActor Equatable {
    /// Groups are equal when they stand for the same folder in the same place,
    /// as SwiftUI compares a view's inputs: a list that redraws leaves them be.
    static func == (lhs: BrowserFolderGroup, rhs: BrowserFolderGroup) -> Bool {
        lhs.folder === rhs.folder && lhs.depth == rhs.depth && lhs.context == rhs.context
            && lhs.inheritedKeptTabID == rhs.inheritedKeptTabID
    }
}

/// The full folder keeps its registration for an owned lift, while ordinary
/// input follows the page role entirely within this interaction leaf.
private struct BrowserFolderReorderContainer: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration

    @Environment(\.sidebarSpaceIsSelected) var isSelected

    func body(content: Content) -> some View {
        content.browserSidebarReorderContainer(
            item: .folder(configuration.dragItem),
            section: configuration.folder.reorderSection,
            reorder: BrowserSidebarReorderContext(
                browser: configuration.browser, spaceAccess: configuration.spaceAccess,
                state: sidebarInteraction.sidebarReorderState),
            isEnabled: (SidebarSpaceRole.permitsInteraction(
                isSelected: isSelected, isAvailable: configuration.isAvailableForDisplay) || isLiftedFolder)
                && configuration.capabilities.supportsOrganization
        )
    }

    private var isLiftedFolder: Bool {
        guard let lift = sidebarInteraction.sidebarReorderState.lift,
            case .folder(let item) = lift.item
        else { return false }
        return item.folderID == configuration.folder.id
            && item.spaceID == configuration.spaceID && item.profileID == configuration.profileID
    }
}

/// The landing slot a folder's tab run keeps open at its end.
///
/// A finger cannot aim at the seam between two rows that touch, so a shell
/// that reserves those places gets a zone of its own here. Where the seam is
/// aimable the reservation would only add an empty band nothing lands in.
private struct BrowserFolderReorderReservation: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration

    @ViewBuilder
    func body(content: Content) -> some View {
        if configuration.capabilities.reservesReorderSectionZones {
            content.browserSidebarReorderSectionReservation(
                .tabs(placement: configuration.folder.location, folderID: configuration.folder.id),
                state: sidebarInteraction.sidebarReorderState
            )
        } else {
            content
        }
    }
}
