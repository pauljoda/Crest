import SwiftUI

struct SavedFolderIcon: View {
    let folder: SavedFolder
    let isExpanded: Bool

    var body: some View {
        Image(
            systemName: BrowserFolderRowPresentationPolicy.systemImage(
                isExpanded: isExpanded
            )
        )
        .frame(width: 18)
        .foregroundStyle(folder.color.color.opacity(0.86))
        .accessibilityHidden(true)
    }
}

#Preview("Saved Folder Icon") {
    let configuration = SavedFolderGroupPreviewFixture.configuration()
    SavedFolderIcon(
        folder: configuration.folder,
        isExpanded: true
    )
}
