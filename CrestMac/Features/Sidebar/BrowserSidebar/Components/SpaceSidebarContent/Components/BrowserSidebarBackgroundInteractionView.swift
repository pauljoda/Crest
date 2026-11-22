import SwiftUI

struct BrowserSidebarBackgroundInteractionView: View {
    let editSpace: () -> Void
    /// Collapses every open folder of the sidebar's Space.
    let collapseAllFolders: () -> Void
    /// Whether the Space has a folder open to collapse.
    let canCollapseAllFolders: () -> Bool
    let createSpace: (() -> Void)?
    /// Adds a Sub-Space after the sidebar's Space, where its window may.
    let createSubSpace: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Dragging the empty sidebar moves the window. Its double-click opens a
        // new tab (`BrowserSidebarEmptySpaceNewTabGesture`) rather than acting
        // as the title bar, as it has since Crest offered it.
        Color.clear
            .contentShape(.rect)
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents()
            .contextMenu {
                ForEach(
                    BrowserSidebarBackgroundAction.all.filter {
                        !$0.requiresSpaceCreation || createSpace != nil && ($0 != .newSubSpace || createSubSpace != nil)
                    }
                ) { action in
                    Button(action.title, systemImage: action.symbol) {
                        withAnimation(
                            action.animatesSidebar ? CrestMotion.disclosure.unlessReducingMotion(reduceMotion) : nil
                        ) {
                            action.perform(on: self)
                        }
                    }
                    .disabled(!action.isEnabled(on: self))
                }
                .crestMenuActionLabelStyle()
            }
            .accessibilityLabel("Sidebar background")
            .accessibilityHint("Drag to move the window or open Space actions")
    }
}
