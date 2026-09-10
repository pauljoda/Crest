import SwiftUI

/// Makes a sidebar row draggable in place: it lifts under the pointer, and its
/// neighbours step aside to show where it will land.
///
/// Uses SwiftUI's own `DragGesture` rather than an AppKit dragging session. The
/// AppKit path never rendered a drag image on macOS 27 and its pan recognizer
/// received only a single sample at mouse-up, so there was nothing to animate.
///
/// Ordinary rows also register their container here. Folder headers only arm
/// the gesture: their enclosing section owns measurement and displacement via
/// `BrowserSidebarReorderContainerModifier`.
struct BrowserSidebarReorderSourceModifier: ViewModifier {
    let item: BrowserSidebarReorderItem
    let section: BrowserSidebarReorderSection
    let reorder: BrowserSidebarReorderContext

    var registersContainer = true
    var isEnabled = true

    @State private var liftSessionToken: BrowserDragSessionToken?
    @State private var rejectedGesture = false

    private var state: BrowserSidebarReorderState { reorder.state }
    private var ownsLift: Bool {
        guard let liftSessionToken else { return false }
        return state.sessionToken == liftSessionToken
    }

    func body(content: Content) -> some View {
        // Selecting a drop destination must not cancel the source's active
        // gesture or discard its frozen geometry before the drop commits.
        let acceptsInput = isEnabled || ownsLift
        Group {
            if registersContainer {
                content.browserSidebarReorderContainer(
                    item: item, section: section, reorder: reorder, isEnabled: acceptsInput)
            } else {
                content
            }
        }
        .modifier(BrowserSidebarReorderLiftGesture(isEnabled: acceptsInput, apply: applyLift))
    }

    /// Feeds a lift's pointer samples into the state. Shared by both platforms so
    /// only the gesture that arms the lift differs.
    private var applyLift: (BrowserSidebarReorderLiftPhase) -> Void {
        { phase in
            if rejectedGesture {
                if case .released = phase {
                    rejectedGesture = false
                    state.suppressActivation()
                }
                return
            }
            // A retained source can receive a callback before SwiftUI has
            // rendered a Space/profile/lock change. Recheck live authorization.
            let continuingLift = ownsLift
            guard sourceIsAvailable,
                continuingLift
                    || (isEnabled && reorder.browser.session.selectedSpaceID == item.spaceAssignment.spaceID)
            else {
                if continuingLift { cancelLift() }
                return
            }
            switch phase {
            case .moved(let startLocation, let location):
                if continuingLift {
                    state.update(pointer: location)
                } else if !state.hasLiftInFlight {
                    let firstID: BrowserSelectionItemID? =
                        switch item {
                        case .tab(let tab): .tab(tab.tabID)
                        case .splitGroup(let group): group.memberTabIDs.first.map(BrowserSelectionItemID.tab)
                        case .folder(let folder): .folder(folder.folderID)
                        }
                    var request = firstID.flatMap { BrowserSidebarSelection.request(for: $0, browser: reorder.browser) }
                    if let captured = request, let space = reorder.browser.selectedSpace {
                        request = reorder.browser.tabMultiSelection.prepareForDrag(captured, in: space)
                        if let id = firstID?.tabID, request?.ids.contains(id) != true {
                            rejectedGesture = true
                            return
                        }
                    }
                    var lifted = item.selecting(request)
                    var liftedSection = section
                    if let request, !lifted.selectionRowIDs.contains(item.id),
                        let space = reorder.browser.selectedSpace,
                        let root = request.rootItems.compactMap(\.folderID).first(where: { root in
                            let subtree = space.folderTree.descendants(of: root).union([root])
                            if let folder = firstID?.folderID { return subtree.contains(folder) }
                            return space.tabs.contains {
                                $0.id == firstID?.tabID && $0.folderID.map(subtree.contains) == true
                            }
                        }), let folder = space.folders.first(where: { $0.id == root })
                    {
                        lifted = .folder(
                            BrowserFolderDragItem(
                                folderID: root, spaceID: space.id,
                                profileID: space.profile.id, selection: request))
                        liftedSection = folder.reorderSection
                    }
                    state.batchValidation = {
                        [weak browser = reorder.browser, weak access = reorder.spaceAccess] target, request in
                        guard let browser, let access else {
                            return String(localized: "The Space is no longer available.")
                        }
                        return BrowserSidebarReorderCommit(browser: browser, spaceAccess: access).batchReason(
                            target, request: request)
                    }
                    state.begin(item: lifted, section: liftedSection, at: startLocation)
                    liftSessionToken = state.sessionToken
                    state.update(pointer: location)
                }
            case .released:
                guard continuingLift else { return }
                self.liftSessionToken = nil
                // Replace the temporary gap with its real row in one layout
                // transaction. The floating preview owns the visible landing.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    guard let drop = state.end(retainingPreview: BrowserSidebarReorderPolicy.drawsOwnLift) else {
                        return
                    }
                    reorder.commit(drop.target, for: drop.item)
                }
            }
        }
    }

    private func cancelLift() {
        guard let liftSessionToken else { return }
        self.liftSessionToken = nil
        state.cancel(session: liftSessionToken)
    }

    /// Used only for pointer actions, not while rendering or measuring rows.
    private var sourceIsAvailable: Bool {
        guard
            let space = BrowserSidebarAccessPolicy.unlockedSpace(
                matching: item.spaceAssignment, in: reorder.browser, accessController: reorder.spaceAccess)
        else { return false }
        switch item {
        case .tab(let tabItem):
            guard let tab = space.tabs.first(where: { $0.id == tabItem.tabID }),
                space.splitGroup(containing: tab.id) == nil
            else {
                return false
            }
            return section == .tabs(placement: tab.placement, folderID: tab.folderID)
        case .folder(let folderItem):
            return space.folders.first(where: { $0.id == folderItem.folderID })?.reorderSection == section
        case .splitGroup(let groupItem):
            let members = space.splitGroupMembers(of: groupItem.groupID)
            guard let first = members.first,
                members.map(\.id) == groupItem.memberTabIDs
            else { return false }
            return section == .tabs(placement: first.placement, folderID: first.folderID)
        }
    }
}

extension View {
    func browserSidebarReorderSource(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection,
        reorder: BrowserSidebarReorderContext,
        registersContainer: Bool = true,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            BrowserSidebarReorderSourceModifier(
                item: item,
                section: section,
                reorder: reorder,
                registersContainer: registersContainer,
                isEnabled: isEnabled
            )
        )
    }
}
