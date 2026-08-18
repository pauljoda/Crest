import Foundation
import SwiftUI

struct MobileBrowserRootLifecycleModifier: ViewModifier {
    let model: MobileBrowserRootModel
    let presentation: MobileBrowserPresentation

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
        isAddressEditing: Binding<Bool>,
        storedSidebarWidth: Binding<Double>
    ) {
        self.model = model
        self.presentation = presentation
        _isAddressEditing = isAddressEditing
        _storedSidebarWidth = storedSidebarWidth
        _runtimeSessionProjection = State(
            initialValue: BrowserRuntimeSessionProjection(
                session: model.browser.session
            )
        )
        _tabRuntimeAssignments = State(
            initialValue: model.browser.session.tabRuntimeAssignments
        )
    }

    func body(content: Content) -> some View {
        let preparedContent =
            content
            .onChange(of: presentation, initial: true) { _, current in
                model.presentationChanged(to: current)
            }
            .task {
                await model.prepareBrowser()
            }
            .modifier(
                MobileBrowserRootSelectionObserver(
                    selection: model.selectionSnapshot,
                    lock: model.lockSnapshot(presentation: presentation),
                    selectionChanged: synchronizeSelection,
                    lockChanged: model.synchronizeLockTransition
                )
            )

        let pageObservedContent =
            preparedContent
            .onChange(of: model.renderedPageSelection, initial: true) { _, selection in
                model.recordRenderedSelection(selection)
            }
            .onChange(of: model.selectedPage?.displayURL) {
                synchronizePageMetadata()
            }
            .onChange(of: model.selectedPage?.title) {
                synchronizePageMetadata()
            }
            .onChange(of: model.selectedPage?.faviconData) {
                synchronizePageMetadata()
            }
            .onChange(of: model.selectedPage?.themeColor) {
                synchronizePageMetadata()
            }
            .onChange(of: model.selectedPage?.completedNavigationCount) {
                model.recordCompletedNavigation(
                    isAddressEditing: isAddressEditing
                )
            }

        let runtimeObservedContent =
            pageObservedContent
            .onChange(of: model.browser.sessionRevision, initial: true) {
                runtimeSessionProjection = BrowserRuntimeSessionProjection(
                    session: model.browser.session
                )
                tabRuntimeAssignments =
                    model.browser.session.tabRuntimeAssignments
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

    private func synchronizePageMetadata() {
        model.synchronizePageMetadata(isAddressEditing: isAddressEditing)
    }
}
