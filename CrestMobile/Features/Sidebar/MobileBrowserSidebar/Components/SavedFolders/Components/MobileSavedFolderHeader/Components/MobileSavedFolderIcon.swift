import SwiftUI

struct MobileSavedFolderIcon: View {
    let folder: SavedFolder
    let isExpanded: Bool

    var body: some View {
        Image(
            systemName: BrowserFolderRowPresentationPolicy.systemImage(
                isExpanded: isExpanded
            )
        )
        .font(.system(size: 17, weight: .medium))
        .frame(width: 20)
        .foregroundStyle(folder.color.color.opacity(0.86))
        .accessibilityHidden(true)
    }
}

#Preview("Mobile Saved Folder Icon", traits: .sizeThatFitsLayout) {
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileSavedFolderIcon(folder: fixture.folder, isExpanded: true)
        .padding()
}
