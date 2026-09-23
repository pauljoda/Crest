import Observation
import SwiftUI

/// Validates and commits a row's reorder session from native input phases.
/// Folder headers use their enclosing section for measurement and displacement.
struct BrowserSidebarReorderSourceModifier: ViewModifier {
    let item: BrowserSidebarReorderItem
    let section: BrowserSidebarReorderSection
    let reorder: BrowserSidebarReorderContext

    var parentItemID: BrowserSidebarReorderItemID?
    var registersContainer = true
    var isEnabled = true

    @Environment(\.browserSidebarWindowDrop) private var windowDrop
    @State private var input = BrowserSidebarReorderInputSession()

    private var state: BrowserSidebarReorderState { reorder.state }
    private var ownsLift: Bool {
        input.ownsLift(in: state)
    }

    func body(content: Content) -> some View {
        // Selecting a drop destination must not cancel the source's active
        // gesture or discard its frozen geometry before the drop commits.
        let acceptsInput = isEnabled || ownsLift
        Group {
            if registersContainer {
                content.browserSidebarReorderContainer(
                    item: item, section: section, reorder: reorder, parentItemID: parentItemID,
                    isEnabled: acceptsInput)
            } else {
                content
            }
        }
        .modifier(BrowserPlatformSidebarReorderLiftGesture(isEnabled: acceptsInput, apply: applyLift))
    }

    /// Keeps captured selection and live source authorization with the shared session.
    private var applyLift: (BrowserSidebarReorderLiftPhase) -> Void {
        { phase in
            if input.liftSessionToken != nil, !ownsLift {
                input.liftSessionToken = nil
                if case .moved = phase { input.rejectedGesture = true }
                return
            }
            if input.rejectedGesture {
                if case .released = phase {
                    input.rejectedGesture = false
                    state.suppressActivation()
                }
                return
            }
            // A retained source can receive a callback before SwiftUI has
            // rendered a Space/profile/lock change. Recheck live authorization.
            if ownsLift {
                input.resume(phase, source: source, reorder: reorder, windowDrop: windowDrop)
                return
            }
            guard source.isAvailable(in: reorder), isEnabled,
                reorder.browser.selectedSpaceID == item.spaceAssignment.spaceID
            else { return }
            switch phase {
            case .moved(let startLocation, let location):
                if !state.hasLiftInFlight {
                    let firstID: BrowserSelectionItemID? =
                        switch item {
                        case .tab(let tab): .tab(tab.tabID)
                        case .splitGroup(let group): group.memberTabIDs.first.map(BrowserSelectionItemID.tab)
                        case .folder(let folder): .folder(folder.folderID)
                        }
                    var request = firstID.flatMap {
                        BrowserSidebarSelection.request(for: $0, browser: reorder.browser, reorder: reorder.state)
                    }
                    if let captured = request, let space = reorder.browser.selectedSpace {
                        request = reorder.browser.tabMultiSelection.prepareForDrag(captured, in: space)
                        if let id = firstID?.tabID, request?.ids.contains(id) != true {
                            input.rejectedGesture = true
                            return
                        }
                    }
                    var lifted = item.selecting(request)
                    var liftedSection = section
                    if let request, let parentItemID, case .splitGroup(let groupID) = parentItemID,
                        lifted.selectionRowIDs.contains(parentItemID), let space = reorder.browser.selectedSpace
                    {
                        lifted = .splitGroup(
                            BrowserSplitGroupDragItem(
                                groupID: groupID, spaceID: space.id, profileID: space.profile.id,
                                memberTabIDs: space.splitGroupMembers(of: groupID).map(\.id), selection: request))
                    }
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
                    input.liftSessionToken = state.sessionToken
                    #if os(macOS)
                        input.retainPointerContinuation(source: source, reorder: reorder, windowDrop: windowDrop)
                    #endif
                    state.update(pointer: location)
                }
            case .released:
                break
            }
        }
    }

    private var source: BrowserSidebarReorderInputSession.Source {
        .init(item: item, section: section, parentItemID: parentItemID)
    }

}

/// Only the input token outlives a lazy row; no SwiftUI State storage is captured.
@Observable
@MainActor
final class BrowserSidebarReorderInputSession {
    var liftSessionToken: BrowserDragSessionToken?
    var rejectedGesture = false

    @MainActor
    struct Source {
        let item: BrowserSidebarReorderItem
        let section: BrowserSidebarReorderSection
        var parentItemID: BrowserSidebarReorderItemID?

        /// Used only for pointer actions, not while rendering or measuring rows.
        func isAvailable(in reorder: BrowserSidebarReorderContext) -> Bool {
            guard
                let space = BrowserSidebarAccessPolicy.unlockedSpace(
                    matching: item.spaceAssignment, in: reorder.browser, accessController: reorder.spaceAccess)
            else { return false }
            switch item {
            case .tab(let tabItem):
                guard let tab = space.tabs.first(where: { $0.id == tabItem.tabID }) else { return false }
                guard space.splitGroup(containing: tab.id).map(BrowserSidebarReorderItemID.splitGroup) == parentItemID
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

    func ownsLift(in state: BrowserSidebarReorderState) -> Bool {
        guard let liftSessionToken else { return false }
        return state.sessionToken == liftSessionToken
    }

    func retainPointerContinuation(
        source: Source, reorder: BrowserSidebarReorderContext, windowDrop: BrowserSidebarWindowDrop?
    ) {
        liftSessionToken = reorder.state.sessionToken
        guard let liftSessionToken else { return }
        reorder.state.retainPointerContinuation(session: liftSessionToken) {
            [
                self, weak state = reorder.state, weak browser = reorder.browser,
                weak access = reorder.spaceAccess
            ] point, released in
            guard let state else { return }
            guard let browser, let access else {
                cancel(in: state)
                return
            }
            let context = BrowserSidebarReorderContext(browser: browser, spaceAccess: access, state: state)
            resume(
                .moved(startLocation: point, location: point), source: source, reorder: context, windowDrop: windowDrop)
            if released {
                resume(.released(previewOwner: .application), source: source, reorder: context, windowDrop: windowDrop)
            }
        }
    }

    func resume(
        _ phase: BrowserSidebarReorderLiftPhase, source: Source,
        reorder: BrowserSidebarReorderContext, windowDrop: BrowserSidebarWindowDrop?
    ) {
        let state = reorder.state
        guard ownsLift(in: state) else { return }
        guard source.isAvailable(in: reorder) else {
            cancel(in: state)
            return
        }
        switch phase {
        case .moved(_, let location):
            if state.pointer != location { state.update(pointer: location) }
        case .released(let previewOwner):
            if let lift = state.liftPreview, windowDrop?.perform(lift) == true {
                cancel(in: state)
                state.suppressActivation()
                return
            }
            liftSessionToken = nil
            // Commit once while the native release event still supplies tear-off coordinates.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                guard let drop = state.end(retainingPreview: previewOwner == .application) else { return }
                reorder.commit(drop.target, for: drop.item)
            }
        }
    }

    func cancel(in state: BrowserSidebarReorderState) {
        guard let liftSessionToken else { return }
        self.liftSessionToken = nil
        state.cancel(session: liftSessionToken)
    }
}

extension View {
    func browserSidebarReorderSource(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection,
        reorder: BrowserSidebarReorderContext,
        parentItemID: BrowserSidebarReorderItemID? = nil,
        registersContainer: Bool = true,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            BrowserSidebarReorderSourceModifier(
                item: item,
                section: section,
                reorder: reorder,
                parentItemID: parentItemID,
                registersContainer: registersContainer,
                isEnabled: isEnabled
            )
        )
    }
}
