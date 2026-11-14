import SwiftUI

/// A group's name: small, semibold and secondary, or in the group's color
/// where the person asked for it, as its header and its drag preview show it.
/// It grows and shrinks with Tab size, as the sidebar's text does.
struct BrowserGroupHeaderTitle: View {
    let folder: FolderStateModel
    let tintsTitle: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(folder.shownTitle)
            .modifier(BrowserGroupNameFont())
            .foregroundStyle(
                tintsTitle
                    ? folder.displayColor.folderTitleColor(onDarkBackground: colorScheme == .dark).color
                    : .secondary
            )
            .lineLimit(1)
    }
}
