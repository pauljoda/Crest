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
///
/// A folder far down a folder that has just opened draws its header at once
/// and what it holds a moment later, once the opening has run, so the rows
/// that show come first. VoiceOver and Switch Control get everything at once.
struct BrowserFolderGroup: View {
    // MARK: - Variables

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let folder: FolderStateModel
    /// How many folders hold this one.
    let depth: Int
    let context: BrowserSidebarListContext
    /// The tabs a collapsed folder around this one keeps on screen, which this
    /// folder shows the way to in place of its contents.
    var inheritedKeptTabIDs: Set<UUID>? = nil

    @Environment(\.sidebarSpacePresentation) private var spacePresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled
    /// Whether the folder still holds back what it holds, which it does only
    /// from when it is first drawn until its turn comes.
    @State private var holdsContents: Bool
    @State private var draftTitle = ""
    @State private var iconRequest: BrowserFolderRuntimeAssignment?
    @State private var colorRequest: BrowserFolderRuntimeAssignment?
    @State private var deletionRequest: BrowserFolderRuntimeAssignment?
    #if os(macOS)
        private var collapsedTabVisibility: BrowserCollapsedFolderTabVisibilityState {
            get { collapsedVisibilityOwner.state }
            nonmutating set { collapsedVisibilityOwner.state = newValue }
        }

        private var collapsedVisibilityOwner: BrowserSidebarFolderVisibility {
            sidebarInteraction.collapsedFolderVisibility(
                for: BrowserFolderRuntimeAssignment(
                    folderID: folder.id, spaceID: context.space.id, profileID: context.space.profileID))
        }
    #else
        @State private var collapsedTabVisibility = BrowserCollapsedFolderTabVisibilityState()
    #endif
    @FocusState private var isTitleFocused: Bool

    /// Whether what the folder holds waits for its turn now.
    private var isHoldingContents: Bool {
        holdsContents && !isVoiceOverEnabled && !isSwitchControlEnabled
    }

    private var configuration: BrowserFolderGroupConfiguration {
        BrowserFolderGroupConfiguration(
            sidebarInteraction: sidebarInteraction, folder: folder, depth: depth, context: context,
            spacePresentation: spacePresentation, inheritedKeptTabIDs: inheritedKeptTabIDs,
            isOpenInClosedFolder: collapsedTabVisibility.isOpenInClosedFolder)
    }

    /// Whether the folder shows as open. Inside a closed folder that draws it
    /// as the way to its kept tabs, opening it also shows everything it holds
    /// there, and the folder stays open once the folder around it opens.
    private var isExpanded: Binding<Bool> {
        Binding {
            configuration.isShownOpen
        } set: { isExpanded in
            guard configuration.isCurrentAndUnlocked else { return }
            if inheritedKeptTabIDs != nil { collapsedTabVisibility.openInClosedFolder(isExpanded) }
            context.browser.setFolderCollapsed(
                folder.id, matching: configuration.assignment, isCollapsed: !isExpanded)
        }
    }

    private var editingFolderRequest: Binding<BrowserFolderRuntimeAssignment?> {
        Binding {
            sidebarInteraction.editingFolderRequest
        } set: {
            sidebarInteraction.editingFolderRequest = $0
        }
    }

    private var interaction: BrowserFolderGroupInteractionContext {
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
            closeAllTabs: closeAllTabs,
            beginTitleEditingIfNeeded: beginTitleEditingIfNeeded,
            commitTitle: commitTitle,
            cancelTitleEditing: cancelTitleEditing,
            deleteFolder: deleteFolder
        )
    }

    // MARK: - Initializers

    /// A folder that `defersContents` holds back what it holds when it is
    /// first drawn, as one far down a list that has just opened does.
    init(
        folder: FolderStateModel, depth: Int, context: BrowserSidebarListContext,
        inheritedKeptTabIDs: Set<UUID>? = nil, defersContents: Bool = false
    ) {
        self.folder = folder
        self.depth = depth
        self.context = context
        self.inheritedKeptTabIDs = inheritedKeptTabIDs
        _holdsContents = State(initialValue: defersContents)
    }

    // MARK: - Actions - Presentation

    var body: some View {
        let configuration = self.configuration
        let interaction = self.interaction
        let showsAllContents = configuration.showsAllContents
        let keptTabIDs = configuration.keptTabIDs(for: collapsedTabVisibility)
        VStack(spacing: 0) {
            BrowserFolderGroupSurface(configuration: configuration, interaction: interaction)
            if showsAllContents ? !isHoldingContents : !keptTabIDs.isEmpty {
                // One list for both: closing keeps the rows of the tabs it
                // keeps, which move up as the rest go, rather than drawing
                // them again apart from the folder's own.
                folderContents(configuration: configuration, keptTabIDs: showsAllContents ? nil : keptTabIDs)
                    .transition(
                        .modifier(
                            active: BrowserFolderContentsReveal(progress: 0),
                            identity: BrowserFolderContentsReveal(progress: 1)))
            }
        }
        .environment(\.browserInteractionCapabilities, context.capabilities)
        .modifier(
            BrowserFolderSectionSurface(
                color: folder.displayColor,
                kind: folder.kind,
                intensity: configuration.displayBranding?.folderColorIntensity ?? 0,
                textColorMode: configuration.displayBranding?.shownTextColorMode ?? .automatic,
                depth: depth,
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
            isActive: !showsAllContents
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
                hasPendingActions: hasPendingActions,
                cancel: clearUnavailableDeferredActions
            )
        )
        .keepsSidebarFolderDrawn(hasPendingActions || isHoldingContents)
        .task { await releaseContents() }
        // Opened inside a closed folder only lasts while that folder stays
        // closed around it, including when the folder draws itself again
        // after leaving the screen.
        .onChange(of: inheritedKeptTabIDs == nil, initial: true) { _, drawsItself in
            if drawsItself { collapsedTabVisibility.closedFolderAroundOpened() }
        }
        .padding(.vertical, BrowserSidebarMetrics.containerSpacing)
    }

    /// Whether a rename, an icon or colour choice, or a deletion is under way,
    /// which the folder's view holds until it ends.
    private var hasPendingActions: Bool {
        sidebarInteraction.editingFolderRequest == configuration.folderRuntimeAssignment
            || colorRequest != nil || iconRequest != nil || deletionRequest != nil
    }

    /// Nested folders are children of the section they move with, so a parent's
    /// measurement, hover surface and lift include the entire expanded subtree.
    /// A closed folder lists only the rows on the way to `keptTabIDs`.
    private func folderContents(configuration: BrowserFolderGroupConfiguration, keptTabIDs: Set<UUID>?) -> some View {
        BrowserSidebarListRows(
            list: configuration.inside, context: context, keptTabIDs: keptTabIDs, defersDistantFolders: true
        ) { items in
            if items.isEmpty { BrowserFolderEmptyRunBand(configuration: configuration) }
        }
        .equatable()
        .browserSidebarReorderSectionIndicator(
            .tabs(placement: folder.location, folderID: folder.id),
            state: sidebarInteraction.sidebarReorderState
        )
        // Each row says its own depth; this is for what the run draws between
        // them, such as the slot a lift leaves.
        .environment(\.sidebarLayerDepth, depth + 1)
        // Rows come and go in place as the folder closes around the tabs it
        // keeps and opens again, rather than sliding up through its title.
        .environment(\.sidebarFolderRowTransition, .opacity)
    }

    /// Draws what the folder holds once its turn comes, after the opening it
    /// waited out. It comes in place, as the rows of a folder that was
    /// already open do. A closed folder, which draws only the tabs it keeps,
    /// lets go without a turn, so it never holds up an open one.
    private func releaseContents() async {
        guard holdsContents else { return }
        do {
            try await Task.sleep(for: .seconds(CrestMotion.disclosureTransition))
            if configuration.showsAllContents { try await BrowserFolderContentsTurns.shared.take() }
        } catch {
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { holdsContents = false }
    }

    // MARK: - Actions - Organization

    private func beginCreatingChild() {
        guard configuration.isCurrentAndUnlocked else { return }
        guard
            let childID = context.browser.addFolder(
                parentID: folder.id,
                matching: configuration.assignment
            )
        else {
            return
        }
        if inheritedKeptTabIDs != nil { expandFoldersAround() }
        isExpanded.wrappedValue = true
        sidebarInteraction.editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: childID,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID
        )
    }

    /// Opens every collapsed folder that holds this one. A folder drawn on a
    /// collapsed folder's way to its kept tabs shows only that way, so a child
    /// made here would stay hidden, and its title could never start editing,
    /// until the folders around it open.
    private func expandFoldersAround() {
        var parentID = folder.parentID
        var visited: Set<UUID> = []
        while let id = parentID, visited.insert(id).inserted, let parent = context.space.folders.model(id) {
            if parent.isCollapsed {
                context.browser.setFolderCollapsed(id, matching: configuration.assignment, isCollapsed: false)
            }
            parentID = parent.parentID
        }
    }

    private func beginRenaming() {
        guard configuration.isCurrentAndUnlocked else { return }
        sidebarInteraction.editingFolderRequest = configuration.folderRuntimeAssignment
    }

    private func toggleExpansion() {
        guard !sidebarInteraction.sidebarReorderState.suppressesActivation,
            sidebarInteraction.editingFolderRequest != configuration.folderRuntimeAssignment,
            configuration.isCurrentAndUnlocked
        else {
            return
        }
        withAnimation(
            CrestMotion.disclosure.unlessReducingMotion(reduceMotion)
        ) {
            let nextExpansion = !configuration.isShownOpen
            collapsedTabVisibility.expansionDidChange(
                isExpanded: nextExpansion,
                selectedTabID: configuration.shownFolderTabID,
                folderTabIDs: configuration.folderTabIDs,
                residentFolderTabIDs: configuration.residentFolderTabIDs
            )
            isExpanded.wrappedValue = nextExpansion
        }
    }

    /// Closes what the folder holds to close, then closes the folder: a
    /// saved folder's loaded tabs unload as their rows' unload control does,
    /// and stay saved, and a group's or an open folder's tabs close together,
    /// as a selection of them does.
    private func closeAllTabs() {
        guard configuration.isCurrentAndUnlocked, configuration.hasTabsToClose else { return }
        if configuration.isShownOpen { toggleExpansion() }
        if folder.location.isDurable {
            context.unload(configuration.loadedFolderTabIDs)
        } else if let request = BrowserSidebarSelection.capture(
            configuration.folderTabIDs.map { .tab($0) }, in: context.browser)
        {
            _ = BrowserTabBatchActions(browser: context.browser, spaceAccess: context.spaceAccess)
                .perform(context.browser.closing(request), for: request)
        }
    }

    private func beginTitleEditingIfNeeded() {
        guard sidebarInteraction.editingFolderRequest == configuration.folderRuntimeAssignment,
            isDeferredAssignmentAvailable(
                configuration.folderRuntimeAssignment
            )
        else {
            isTitleFocused = false
            return
        }
        draftTitle = folder.title
        Task { @MainActor in
            isTitleFocused = true
        }
    }

    private func commitTitle() {
        guard let request = sidebarInteraction.editingFolderRequest,
            request == configuration.folderRuntimeAssignment
        else { return }
        sidebarInteraction.editingFolderRequest = nil
        guard isDeferredAssignmentAvailable(request) else { return }
        context.browser.renameFolder(
            request.folderID,
            matching: request.spaceAssignment,
            title: draftTitle
        )
    }

    private func cancelTitleEditing() {
        guard sidebarInteraction.editingFolderRequest == configuration.folderRuntimeAssignment else {
            return
        }
        draftTitle = folder.title
        sidebarInteraction.editingFolderRequest = nil
    }

    private func deleteFolder() {
        guard let request = deletionRequest else { return }
        deletionRequest = nil
        guard isDeferredAssignmentAvailable(request) else { return }
        context.browser.deleteFolderAndContents(request.folderID, matching: request.spaceAssignment)
    }

    private var folderColorBinding: Binding<BrandColor> {
        Binding(
            get: { folder.displayColor },
            set: { color in
                guard let request = colorRequest,
                    isDeferredAssignmentAvailable(request)
                else { return }
                context.browser.setFolderColor(
                    request.folderID,
                    matching: request.spaceAssignment,
                    color: color
                )
            }
        )
    }

    private var colorPresentation: Binding<Bool> {
        Binding {
            guard let request = colorRequest else { return false }
            return isDeferredAssignmentAvailable(request)
        } set: { isPresented in
            if isPresented, configuration.isCurrentAndUnlocked {
                colorRequest = configuration.folderRuntimeAssignment
            } else if !isPresented {
                colorRequest = nil
            }
        }
    }

    private var folderSymbolBinding: Binding<String> {
        Binding(
            get: { folder.displaySymbol },
            set: { symbol in
                guard let request = iconRequest,
                    isDeferredAssignmentAvailable(request)
                else { return }
                context.browser.setFolderSymbol(
                    request.folderID,
                    matching: request.spaceAssignment,
                    symbol: symbol
                )
            }
        )
    }

    private var iconPresentation: Binding<Bool> {
        Binding {
            guard let request = iconRequest else { return false }
            return isDeferredAssignmentAvailable(request)
        } set: { isPresented in
            if isPresented, configuration.isCurrentAndUnlocked {
                iconRequest = configuration.folderRuntimeAssignment
            } else if !isPresented {
                iconRequest = nil
            }
        }
    }

    private var deletionPresentation: Binding<Bool> {
        Binding {
            guard let request = deletionRequest else { return false }
            return isDeferredAssignmentAvailable(request)
        } set: { isPresented in
            if isPresented, configuration.isCurrentAndUnlocked {
                deletionRequest = configuration.folderRuntimeAssignment
            } else if !isPresented {
                deletionRequest = nil
            }
        }
    }

    private func isDeferredAssignmentAvailable(
        _ request: BrowserFolderRuntimeAssignment
    ) -> Bool {
        request == configuration.folderRuntimeAssignment && configuration.isCurrentAndUnlocked
    }

    private func clearUnavailableDeferredActions() {
        if let request = sidebarInteraction.editingFolderRequest,
            request == configuration.folderRuntimeAssignment,
            !isDeferredAssignmentAvailable(request)
        {
            sidebarInteraction.editingFolderRequest = nil
            isTitleFocused = false
        }
        if let request = iconRequest,
            !isDeferredAssignmentAvailable(request)
        {
            iconRequest = nil
        }
        if let request = colorRequest,
            !isDeferredAssignmentAvailable(request)
        {
            colorRequest = nil
        }
        if let request = deletionRequest,
            !isDeferredAssignmentAvailable(request)
        {
            deletionRequest = nil
        }
    }
}

extension BrowserFolderGroup: @MainActor Equatable {
    /// Groups are equal when they stand for the same folder in the same place,
    /// as SwiftUI compares a view's inputs: a list that redraws leaves them be.
    static func == (lhs: BrowserFolderGroup, rhs: BrowserFolderGroup) -> Bool {
        lhs.folder === rhs.folder && lhs.depth == rhs.depth && lhs.context == rhs.context
            && lhs.inheritedKeptTabIDs == rhs.inheritedKeptTabIDs
    }
}

/// Hands the folders that held back what they hold their turns one after
/// another, each a beat after the one before it, so however busy the window
/// is, no two draw what they hold in the same frame.
@MainActor
private final class BrowserFolderContentsTurns {
    // MARK: - Static Variables

    static let shared = BrowserFolderContentsTurns()

    /// How long after one folder takes its turn the next may take its own:
    /// a little over a frame, so the first is drawn before the next starts.
    private static let interval: Duration = .milliseconds(20)

    // MARK: - Variables

    /// The turn asked for last, which the next waits on.
    private var last: Task<Void, Never>?

    // MARK: - Actions - Turns

    /// Waits for every turn asked for before this one, then a beat. Throws
    /// when the asking task was cancelled meanwhile, as when its folder went.
    /// A cancelled turn skips its beat, so the turns after it go on without
    /// waiting for it.
    func take() async throws {
        let previous = last
        let turn = Task { @MainActor in
            await previous?.value
            try? await Task.sleep(for: Self.interval)
        }
        last = turn
        await withTaskCancellationHandler {
            await turn.value
        } onCancel: {
            turn.cancel()
        }
        try Task.checkCancellation()
    }
}

/// The full folder keeps its registration for an owned lift, while ordinary
/// input follows the page role entirely within this interaction leaf.
private struct BrowserFolderReorderContainer: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

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

/// Shows a folder's contents from the top down as the rows below make room for
/// them, and covers them again from the bottom up as they close, so nothing
/// below slides across contents still appearing. However deep the contents
/// go, they arrive as one piece, the way a folder of tabs alone does.
private struct BrowserFolderContentsReveal: ViewModifier {
    /// How much of the contents shows, from the top.
    let progress: CGFloat

    /// A clip leaves hit testing alone, so contents on their way out stop
    /// taking clicks as they start to close, and a click lands on the row
    /// that is sliding up over them.
    func body(content: Content) -> some View {
        content
            .clipShape(BrowserFolderRevealShape(progress: progress))
            .allowsHitTesting(progress >= 1)
    }
}

/// The part of a folder's contents a reveal shows. It reaches past their top
/// and sides by a selected tab's glow, and past their bottom once they are all
/// shown, so at rest it hides nothing. While they are still coming in, its
/// bottom edge is the top of the row below.
private struct BrowserFolderRevealShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let glow = BrowserTabSelectionGlow.outset
        let bottom = rect.minY + rect.height * progress + (progress >= 1 ? glow : 0)
        return Path(
            CGRect(
                x: rect.minX - glow, y: rect.minY - glow, width: rect.width + glow * 2,
                height: bottom - rect.minY + glow))
    }
}

/// The landing slot a folder's tab run keeps open at its end.
///
/// A finger cannot aim at the seam between two rows that touch, so a shell
/// that reserves those places gets a zone of its own here. Where the seam is
/// aimable the reservation would only add an empty band nothing lands in.
private struct BrowserFolderReorderReservation: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

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
