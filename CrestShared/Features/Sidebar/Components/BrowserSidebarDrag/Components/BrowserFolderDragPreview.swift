import SwiftUI

struct BrowserFolderDragPreview: View {
    let folder: SavedFolder
    var rowWidth = BrowserTabDragPreviewLayout.rowSize.width

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: CrestRadius.control,
            style: .continuous
        )

        HStack(spacing: CrestSpacing.small) {
            Image(systemName: folder.symbol)
                .foregroundStyle(folder.color.color.opacity(0.86))
                .frame(width: 20)
            Text(folder.title)
                .lineLimit(1)
            Spacer(minLength: CrestSpacing.small)
        }
        .padding(.horizontal, CrestSpacing.medium)
        .frame(
            width: BrowserFolderDragPreviewLayout.width(for: rowWidth),
            height: BrowserFolderDragPreviewLayout.height
        )
        .background(CrestColor.selectedSurface, in: shape)
        .overlay {
            shape.strokeBorder(CrestColor.subtleBorder, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.title) folder")
    }
}
