import SwiftUI

struct PinnedTabOrganizationMenu: View {
    let tab: BrowserTab
    let assignment: BrowserTabRuntimeAssignment
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let isLoaded: Bool
    let dragState: BrowserTabDragState?
    let unload: ((BrowserTabRuntimeAssignment) -> Void)?
    let pullNewIcon: ((BrowserTabRuntimeAssignment) -> Void)?
    let restoreSavedLocation: ((BrowserTabRuntimeAssignment) -> Void)?
    let renameTab: () -> Void

    var body: some View {
        BrowserTabOrganizationMenu(
            tab: tab,
            assignment: assignment,
            browser: browser,
            spaceAccess: spaceAccess,
            isLoaded: isLoaded,
            unload: unloadAction,
            pullNewIcon: pullNewIconAction,
            restoreSavedLocation: restoreSavedLocationAction,
            renameTab: renameTab
        )
        .tint(.primary)
        .onAppear(perform: contextMenuDidOpen)
        .onDisappear(perform: contextMenuDidClose)
    }

    private var unloadAction: ((TabID) -> Void)? {
        guard let unload else { return nil }
        return { _ in unload(assignment) }
    }

    private var pullNewIconAction: (() -> Void)? {
        guard let pullNewIcon else { return nil }
        return { pullNewIcon(assignment) }
    }

    private var restoreSavedLocationAction: (() -> Void)? {
        guard let restoreSavedLocation else { return nil }
        return { restoreSavedLocation(assignment) }
    }

    private func contextMenuDidOpen() {
        dragState?.contextMenuDidOpen(for: assignment)
    }

    private func contextMenuDidClose() {
        dragState?.contextMenuDidClose(for: assignment)
    }
}
