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
                model.hostWindowFocusChanged(isFocused)
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
            .onChange(of: model.browser.selectedTab?.url) { model.synchronizePageMetadata() }
            .onChange(of: model.pages.activePage?.live.displayURL) {
                model.synchronizePageMetadata()
            }

        let runtimeObservedContent =
            pageObservedContent
            .onChange(of: model.browser.sessionRevision, initial: true) {
                runtimeSessionProjection = BrowserRuntimeSessionProjection(
                    session: model.browser.session
                )
                model.reconcilePages()
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
            .onChange(of: model.chrome.noticeRevision) { _, revision in
                model.presentNotice(
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
                    windowID: model.windowState?.id,
                    spaceAccess: model.spaceAccess,
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
