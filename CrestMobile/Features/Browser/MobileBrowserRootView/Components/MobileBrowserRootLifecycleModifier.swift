import Foundation
import SwiftUI

struct MobileBrowserRootLifecycleModifier: ViewModifier {
    let model: MobileBrowserRootModel
    let presentation: MobileBrowserPresentation
    /// Opens a new tab with its address field focused, for a launch that
    /// starts on one.
    let openNewTab: () -> Void
    /// Puts search up over the shown tab by itself, for a launch that starts
    /// on it or a person back after a while away; false when something else
    /// holds the window.
    let presentSearch: () -> Bool

    @Environment(\.scenePhase) private var scenePhase
    @Binding var isAddressEditing: Bool
    @Binding var storedSidebarWidth: Double
    @State private var runtimeSessionProjection: BrowserRuntimeSessionProjection
    /// Which tab belongs to which Space and profile. Page residency is what this
    /// drives, so it changes only when a tab is added, removed, or moved — not
    /// when one of them merely finishes a navigation.
    @State private var tabRuntimeAssignments: Set<BrowserTabRuntimeAssignment>

    init(
        model: MobileBrowserRootModel,
        presentation: MobileBrowserPresentation,
        openNewTab: @escaping () -> Void,
        presentSearch: @escaping () -> Bool,
        isAddressEditing: Binding<Bool>,
        storedSidebarWidth: Binding<Double>
    ) {
        self.model = model
        self.presentation = presentation
        self.openNewTab = openNewTab
        self.presentSearch = presentSearch
        _isAddressEditing = isAddressEditing
        _storedSidebarWidth = storedSidebarWidth
        _runtimeSessionProjection = State(
            initialValue: model.pages.runtimeProjection
        )
        _tabRuntimeAssignments = State(
            initialValue: model.pages.tabRuntimeAssignments
        )
    }

    func body(content: Content) -> some View {
        let preparedContent =
            content
            .task {
                await model.prepareBrowser(openNewTab: openNewTab, presentSearch: presentSearch)
            }
            .onChange(of: scenePhase) { _, phase in
                sceneMoved(to: phase)
            }
            .modifier(
                BrowserRootSelectionObserver(
                    selection: model.selectionSnapshot,
                    lock: model.lockSnapshot(presentation: presentation),
                    // A Space already locked when the shell appears still needs
                    // its locked arrangement — the tab viewer rather than a
                    // page — so the first evaluation counts as a transition.
                    evaluatesLockInitially: true,
                    selectionChanged: synchronizeSelection,
                    lockChanged: model.synchronizeLockTransition
                )
            )

        let pageObservedContent =
            preparedContent
            .onChange(of: model.selectedPage?.live.displayURL) {
                synchronizePageMetadata()
            }
            .onChange(of: isAddressEditing) { _, isEditing in
                guard !isEditing else { return }
                model.restoreAddress()
            }

        let runtimeObservedContent =
            pageObservedContent
            .onChange(of: model.browser.sessionRevision, initial: true) {
                model.browser.followSession()
                runtimeSessionProjection = model.pages.runtimeProjection
                tabRuntimeAssignments =
                    model.pages.tabRuntimeAssignments
            }
            // Blocking holds for every Space alike, so the device's level
            // reaches the pages without any change to the session.
            .onChange(of: model.browser.core.state.contentBlockingPolicy) {
                runtimeSessionProjection = model.pages.runtimeProjection
            }
            .onChange(of: tabRuntimeAssignments, initial: true) {
                model.reconcileResidentPages()
            }
            .onChange(
                of: runtimeSessionProjection.tabIconState,
                initial: true
            ) {
                model.reconcileTabIcons()
            }
            .onChange(
                of: runtimeSessionProjection.contentBlockingState,
                initial: true
            ) {
                model.reconcileContentBlocking()
            }
            .onChange(of: model.browser.core.state.contentRuleLists) {
                model.reloadContentBlocking()
            }
            .onChange(of: model.browser.core.state.blockingSites) {
                model.reconcileContentBlocking()
            }
            .onChange(
                of: runtimeSessionProjection.credentialAccessState,
                initial: true
            ) {
                model.reconcileCredentialAccess()
            }

        return
            runtimeObservedContent
            .onChange(of: storedSidebarWidth) { _, width in
                model.restoreSidebarWidth(CGFloat(width))
            }
            .onChange(
                of: model.navigation.regularSidebarPresentation
            ) { _, presentation in
                model.regularSidebarPresentationChanged(presentation)
            }
            .onChange(of: model.lockedSpaceIDs, initial: true) { _, spaceIDs in
                model.relockProtectedSpaces(spaceIDs)
            }
    }

    private func synchronizeSelection(
        _ previous: MobileBrowserRootSelectionSnapshot,
        _ current: MobileBrowserRootSelectionSnapshot
    ) {
        guard model.synchronizeSelection(from: previous, to: current) else {
            return
        }
        isAddressEditing = false
        BrowserAddressFocusDismissal.dismiss()
    }

    /// Notes the window leaving for the background, and greets a person
    /// back after a while with search, when that is their startup choice.
    private func sceneMoved(to phase: ScenePhase) {
        let shownTabID = model.browser.shownTab?.id
        if phase == .background {
            model.greeting.leave(showing: shownTabID)
        } else if phase == .active, model.greeting.comesBack(showing: shownTabID), model.greetsReturnWithSearch {
            _ = presentSearch()
        }
    }

    private func synchronizePageMetadata() {
        model.synchronizePageMetadata(isAddressEditing: isAddressEditing)
    }
}
