import SwiftUI

/// The shell's seat for anything travelling on the pointer.
///
/// Draws nothing itself. A travelling preview cannot be drawn reliably by the
/// view tree at all — the page is an AppKit view and paints above every SwiftUI
/// sibling in the same host, and the chrome, insets, and transitions it passes
/// through clip it everywhere else — so this layer hands it to a window ordered
/// above the whole browser window and lets that draw it, for the whole gesture.
///
/// It resolves what the gesture states name and passes it down, which is the only
/// thing the window cannot work out for itself: a drag carries identifiers, and a
/// preview shows a real row or a real card.
///
/// The two gestures are mutually exclusive by construction — both own the pointer
/// outright — so the carried card is asked first and the sidebar lift answers when
/// there is none.
struct BrowserRootDragPreviewLayer: View {
    let model: BrowserRootModel
    let reduceMotion: Bool

    var body: some View {
        BrowserDragPreviewWindowBridge(content: content)
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
        guard let lift = model.browser.sidebarReorderState.floatingLift,
            let space = model.browser.selectedSpace,
            let subject = subject(for: lift.item, in: space)
        else { return nil }
        return BrowserSidebarLiftPreviewContent(
            subject: subject,
            lift: lift,
            reduceMotion: reduceMotion
        )
    }

    private func subject(
        for item: BrowserSidebarReorderItem,
        in space: BrowserSpace
    ) -> BrowserSidebarLiftPreviewSubject? {
        switch item {
        case .tab(let tab):
            return space.tabs.first { $0.id == tab.tabID }
                .map(BrowserSidebarLiftPreviewSubject.tab)
        case .folder(let folder):
            return space.folders.first { $0.id == folder.folderID }
                .map(BrowserSidebarLiftPreviewSubject.folder)
        case .splitGroup(let group):
            // A run that has already lost its members has nothing to draw; the
            // drag itself is ended by the same change.
            let members = space.splitGroupMembers(of: group.groupID)
            return members.isEmpty ? nil : .splitGroup(members)
        }
    }
}

#Preview("Browser Root Drag Preview Layer") {
    BrowserRootDragPreviewLayer(
        model: BrowserRootPreviewFixture.makeModel(),
        reduceMotion: false
    )
    .frame(width: 1, height: 1)
}
