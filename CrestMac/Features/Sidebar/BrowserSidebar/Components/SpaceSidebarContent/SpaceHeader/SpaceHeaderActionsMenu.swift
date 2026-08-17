import SwiftUI

struct SpaceHeaderActionsMenu: View {
    let isPrivateBrowsing: Bool
    let openNewTab: () -> Void
    let createFolder: () -> Void
    let showHistory: () -> Void
    let showExtensions: () -> Void
    let cleanup: () -> Void

    var body: some View {
        Menu {
            Button("New Tab", systemImage: "plus", action: openNewTab)
            Button(
                "New Folder",
                systemImage: "folder.badge.plus",
                action: createFolder
            )
            Button(
                "History",
                systemImage: "clock.arrow.circlepath",
                action: showHistory
            )
            if isPrivateBrowsing {
                Label(
                    "Extensions Off in Private Browsing",
                    systemImage: "puzzlepiece.extension"
                )
                .foregroundStyle(.secondary)
            } else {
                Button(
                    "Extensions",
                    systemImage: "puzzlepiece.extension",
                    action: showExtensions
                )
            }
            Button(
                "Clean Up Current Tabs",
                systemImage: "sparkles",
                action: cleanup
            )
        } label: {
            Image(systemName: "ellipsis")
                .frame(
                    width: BrowserSidebarMetrics.spaceActionsControlSize,
                    height: BrowserSidebarMetrics.spaceActionsControlSize
                )
        }
        .tint(.primary)
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Space Actions")
    }
}
