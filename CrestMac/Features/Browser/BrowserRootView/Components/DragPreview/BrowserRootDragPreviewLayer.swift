import SwiftUI

/// Resolves lifted items for the inert preview window above browser content.
/// A carried split card takes precedence over a sidebar lift.
struct BrowserRootDragPreviewLayer: View {
    let model: BrowserRootModel
    let reduceMotion: Bool

    var body: some View {
        BrowserDragPreviewWindowBridge(
            content: content,
            onSidebarLandingComplete: model.sidebarInteraction.sidebarReorderState.finishLanding,
            onSidebarLandingArrived: model.sidebarInteraction.sidebarReorderState.revealLanding
        )
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var content: BrowserDragPreviewWindowContent? {
        if let card = splitCardLiftContent {
            return .splitCardLift(card)
        }
        if let sidebar = sidebarLiftContent {
            return .sidebarLift(sidebar)
        }
        return nil
    }

    /// A carried card always belongs to the Space on show: only presented cards
    /// can be picked up, and a Space change ends the carry with the row it came
    /// from.
    private var splitCardLiftContent: BrowserSplitCardLiftPreviewContent? {
        guard let lift = model.splitCardLift.lift,
            let space = model.browser.selectedSpace,
            let tab = space.tabs.first(where: { $0.id == lift.tabID })
        else { return nil }
        return BrowserSplitCardLiftPreviewContent(
            tab: tab,
            profileID: space.profile.id,
            snapshot: lift.snapshot,
            origin: lift.previewOrigin,
            size: lift.cardSize,
            grabFraction: lift.grabFraction,
            isSettling: lift.isSettling,
            reduceMotion: reduceMotion
        )
    }

    /// A lifted row always belongs to the Space on show: the sidebar only offers
    /// the selected Space's rows as drag sources, so a lift that reaches this
    /// point is one of these by construction.
    private var sidebarLiftContent: BrowserSidebarLiftPreviewContent? {
        guard let lift = model.sidebarInteraction.sidebarReorderState.liftPreview,
            let space = model.browser.selectedSpace,
            let subject = subject(for: lift.item, in: space)
        else { return nil }
        return BrowserSidebarLiftPreviewContent(
            subject: subject,
            lift: lift,
            reduceMotion: reduceMotion,
            selectedTabID: space.selectedTabID,
            loadedTabIDs: model.pages.retainedTabIDs
        )
    }

    private func subject(
        for item: BrowserSidebarReorderItem,
        in space: BrowserSpace
    ) -> BrowserSidebarLiftPreviewSubject? {
        if item.selection != nil, let lift = model.sidebarInteraction.sidebarReorderState.liftPreview {
            let rows = BrowserSidebarSelectionPreviewRow.resolve(lift.previewRows, in: space) { folderID in
                model.sidebarInteraction.sidebarReorderState.folderPreviewRows(
                    for: .folder(
                        BrowserFolderDragItem(
                            folderID: folderID, spaceID: space.id, profileID: space.profile.id)))
            }
            return rows.isEmpty ? nil : .selection(rows)
        }
        switch item {
        case .tab(let tab):
            return space.tabs.first { $0.id == tab.tabID }
                .map(BrowserSidebarLiftPreviewSubject.tab)
        case .folder(let folder):
            let rows = BrowserFolderDragPreviewRow.resolve(
                model.sidebarInteraction.sidebarReorderState.liftPreview?.previewRows ?? [],
                in: space, rootFolderID: folder.folderID)

            return space.folders.first { $0.id == folder.folderID }
                .map { .folder($0, rows: rows) }
        case .splitGroup(let group):
            // A run that has already lost its members has nothing to draw; the
            // drag itself is ended by the same change.
            let members = space.splitGroupMembers(of: group.groupID)
            return members.isEmpty ? nil : .splitGroup(members)
        }
    }
}
