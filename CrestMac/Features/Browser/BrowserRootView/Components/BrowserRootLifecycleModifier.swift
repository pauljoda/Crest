import Foundation
import SwiftUI

struct BrowserRootLifecycleModifier: ViewModifier {
    let model: BrowserRootModel
    let persistSidebarWidth: (Double) -> Void
    @Binding var storedSidebarWidth: Double
    @State private var runtimeSessionProjection: BrowserRuntimeSessionProjection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: BrowserRootModel,
        storedSidebarWidth: Binding<Double>,
        persistSidebarWidth: @escaping (Double) -> Void = { _ in }
    ) {
        self.model = model
        self.persistSidebarWidth = persistSidebarWidth
        _storedSidebarWidth = storedSidebarWidth
        _runtimeSessionProjection = State(
            initialValue: BrowserRuntimeSessionProjection(
                session: model.browser.session
            )
        )
    }

    func body(content: Content) -> some View {
        let preparedContent =
            content
            .task {
                await model.prepareBrowser()
            }
            .onChange(of: model.isWindowFocused, initial: true) {
                _, isFocused in
                model.extensionHostWindowFocusChanged(isFocused)
            }
            .modifier(
                BrowserRootSelectionObserver(
                    selection: model.selectionSnapshot,
                    lock: model.selectedSpaceIsLocked,
                    // A window with no locked-Space arrangement of its own has
                    // nothing to do about a lock that is already up when it
                    // appears; `prepareBrowser` settles that case.
                    evaluatesLockInitially: false,
                    selectionChanged: synchronizeSelection,
                    lockChanged: { _, _ in
                        model.synchronizeAfterLockChange()
                    }
                )
            )

        let pageObservedContent =
            preparedContent
            .onChange(of: model.pages.activePage?.displayURL) {
                model.synchronizePageMetadata()
            }
            .onChange(of: model.pages.activePage?.title) {
                model.synchronizePageMetadata()
            }
            .onChange(of: model.pages.activePage?.faviconData) {
                model.synchronizePageMetadata()
            }
            .onChange(of: model.pages.activePage?.themeColor) {
                model.synchronizePageMetadata()
            }
            .onChange(of: model.pages.activePage?.completedNavigationCount) {
                model.recordCompletedNavigation()
            }
            .onChange(of: model.pages.activePage?.isLoading) {
                model.reconcileExtensionTabActivity()
            }
            .onChange(of: model.pages.activePage?.readerModeState) {
                model.reconcileExtensionTabActivity()
            }

        let runtimeObservedContent =
            pageObservedContent
            .onChange(of: model.browser.sessionRevision, initial: true) {
                runtimeSessionProjection = BrowserRuntimeSessionProjection(
                    session: model.browser.session
                )
            }
            .onChange(
                of: runtimeSessionProjection.extensionState,
                initial: true
            ) {
                model.reconcileExtensions()
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

        let chromeObservedContent =
            runtimeObservedContent
            .onChange(of: storedSidebarWidth) { _, width in
                model.restoreSidebarWidth(CGFloat(width))
                persistSidebarWidth(width)
            }
            .onChange(of: model.chrome.urlCopyFeedbackRevision) { _, revision in
                model.presentURLCopyFeedback(
                    revision: revision,
                    reduceMotion: reduceMotion
                )
            }
            .onChange(of: model.chrome.pageZoomFeedbackRevision) { _, revision in
                model.presentPageZoomFeedback(
                    revision: revision,
                    reduceMotion: reduceMotion
                )
            }
            .onChange(of: model.chrome.columnVisibility) {
                model.columnVisibilityChanged(reduceMotion: reduceMotion)
            }
            .onChange(of: model.lockedSpaceIDs, initial: true) { _, spaceIDs in
                model.relockProtectedSpaces(spaceIDs)
            }

        return
            chromeObservedContent
            .focusedSceneValue(
                \.browserCommandContext,
                BrowserCommandContext(
                    browser: model.browser,
                    pages: model.pages,
                    chrome: model.chrome,
                    windowID: model.windowState?.id
                )
            )
    }

    /// A Space change and a tab change are different work, so the transition is
    /// split here rather than inside the observer: moving Space resets the
    /// address field and leaves the page swap to the content selection policy,
    /// while a tab change performs it.
    private func synchronizeSelection(
        _ previous: BrowserRootSelectionSnapshot,
        _ current: BrowserRootSelectionSnapshot
    ) {
        if previous.spaceID != current.spaceID {
            model.synchronizeAfterSpaceChange()
        } else if previous.tabID != current.tabID {
            model.synchronizeAfterSelectionChange()
        }
    }
}
