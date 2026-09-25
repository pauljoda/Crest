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
                    guard let (lifted, liftedSection) = liftedItem(in: reorder) else {
                        input.rejectedGesture = true
                        return
                    }
                    state.begin(
                        item: lifted, section: liftedSection, at: startLocation, plan: reorder.plan(for: lifted))
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

    /// What pulling this row lifts: the row alone, or the window's selection
    /// when it holds the row, as the core previews it. A selection lifts as
    /// the split or folder around this row when one of its picks is that
    /// split or holds this row. Pinned tabs a selection would carry with
    /// others are let go first; nil when that leaves this row behind.
    private func liftedItem(
        in reorder: BrowserSidebarReorderContext
    ) -> (BrowserSidebarReorderItem, BrowserSidebarReorderSection)? {
        let browser = reorder.browser
        let firstID: BrowserSelectionItemID? =
            switch item {
            case .tab(let tab): .tab(tab.tabID)
            case .splitGroup(let group): group.memberTabIDs.first.map(BrowserSelectionItemID.tab)
            case .folder(let folder): .folder(folder.folderID)
            }
        guard let firstID, var captured = BrowserSidebarSelection.capture(for: firstID, in: browser) else {
            return (item, section)
        }
        if let remaining = browser.tabMultiSelection.releasePinnedTabs(from: captured) {
            guard let recaptured = BrowserSidebarSelection.capture(remaining, in: browser),
                firstID.tabID.map(recaptured.ids.contains) ?? true
            else { return nil }
            captured = recaptured
        }
        guard let space = browser.spaceModel(item.spaceAssignment.spaceID) else { return nil }
        var lifted = item.selecting(captured)
        var liftedSection = section
        if let parentItemID, case .splitGroup(let groupID) = parentItemID, lifted.selectionRowIDs.contains(parentItemID)
        {
            lifted = .splitGroup(
                BrowserSplitGroupDragItem(
                    groupID: groupID, spaceID: space.id, profileID: space.profileID,
                    memberTabIDs: space.splitMembers(of: groupID).map(\.id), selection: captured))
        }
        if !lifted.selectionRowIDs.contains(item.id),
            let root = captured.rootItems.compactMap(\.folderID).first(where: { root in
                let holds = Set(space.folderChoices(inside: root).map(\.id)).union([root])
                if let folder = firstID.folderID { return holds.contains(folder) }
                return space.tabIDs(inFolder: root).contains { $0 == firstID.tabID }
            }), let folder = space.folders.model(root)
        {
            lifted = .folder(
                BrowserFolderDragItem(
                    folderID: root, spaceID: space.id, profileID: space.profileID, selection: captured))
            liftedSection = folder.reorderSection
        }
        return (lifted, liftedSection)
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

        /// Whether the row still stands where it was lifted from: the Space
        /// has the same profile and still lists the row there. A locked Space's
        /// lift is the core's to refuse, in its own words.
        /// Used only for pointer actions, not while rendering or measuring rows.
        func isAvailable(in reorder: BrowserSidebarReorderContext) -> Bool {
            let assignment = item.spaceAssignment
            guard let space = reorder.browser.spaceModel(assignment.spaceID), space.profileID == assignment.profileID
            else { return false }
            switch item {
            case .tab(let tabItem):
                guard let tab = space.tabs.model(tabItem.tabID),
                    space.shownSplit(containing: tab.id).map(BrowserSidebarReorderItemID.splitGroup) == parentItemID
                else { return false }
                return section == .tabs(placement: tab.placement, folderID: tab.folderID)
            case .folder(let folderItem):
                return space.folders.model(folderItem.folderID)?.reorderSection == section
            case .splitGroup(let groupItem):
                let members = space.splitMembers(of: groupItem.groupID)
                guard let first = members.first, members.map(\.id) == groupItem.memberTabIDs else { return false }
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
                reorder.commit(drop)
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
