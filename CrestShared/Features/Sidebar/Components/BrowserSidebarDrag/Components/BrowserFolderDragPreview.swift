import SwiftUI

struct BrowserFolderDragPreview: View {
    let folder: BrowserFolder
    var rowWidth = BrowserTabDragPreviewLayout.rowSize.width
    var sourceHeight: CGFloat = BrowserFolderDragPreviewLayout.height
    var rows: [BrowserFolderDragPreviewRow] = []
    var profileID: UUID?
    var loadedTabIDs: Set<TabID>?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CrestLayout.sidebarControlCornerRadius, style: .continuous)
        let width = BrowserFolderDragPreviewLayout.width(for: rowWidth)

        ZStack(alignment: .topLeading) {
            folderHeader(folder)
                .frame(height: BrowserFolderDragPreviewLayout.height)
            ForEach(rows) { row in
                rowContent(row)
                    .frame(width: width, height: rowHeight(row), alignment: .topLeading)
                    .offset(y: row.frame.minY)
            }
        }
        .frame(width: width, height: max(BrowserFolderDragPreviewLayout.height, sourceHeight), alignment: .topLeading)
        .background(CrestColor.selectedSurface, in: shape)
        .background(.regularMaterial, in: shape)
        .overlay {
            shape.fill(folder.color.color.opacity(0.12))
            shape.strokeBorder(folder.color.color.opacity(0.35), lineWidth: 0.5)
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(folder.title) folder")
    }

    private func folderHeader(_ folder: BrowserFolder, depth: Int = 0) -> some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: folder.symbol)
                .foregroundStyle(folder.color.color.opacity(0.86))
                .frame(width: 20)
            Text(folder.title).lineLimit(1)
            Spacer(minLength: CrestSpacing.small)
        }
        .padding(.leading, CrestSpacing.medium + CGFloat(depth) * BrowserFolderLayout.nestingIndent)
        .padding(.trailing, CrestSpacing.medium)
    }

    @ViewBuilder
    private func rowContent(_ row: BrowserFolderDragPreviewRow) -> some View {
        switch row.content {
        case .folder(let child, let depth):
            folderHeader(child, depth: depth)
        case .tab(let tab):
            tabLine(tab, leadingInset: max(BrowserFolderLayout.nestingIndent, row.frame.minX))
        case .splitGroup(let members):
            VStack(spacing: 0) {
                Label("\(members.count)", systemImage: "rectangle.split.2x1")
                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(members) { tab in tabLine(tab, leadingInset: 0).frame(maxHeight: .infinity) }
            }
            .padding(CrestSpacing.extraSmall)
            .background(CrestColor.chromeSurface, in: .rect(cornerRadius: CrestRadius.control))
            .padding(.leading, max(BrowserFolderLayout.nestingIndent, row.frame.minX))
        }
    }

    private func tabLine(_ tab: BrowserTab, leadingInset: CGFloat) -> some View {
        HStack(spacing: CrestSpacing.small) {
            if let profileID {
                TabFaviconView(tab: tab, profileID: profileID, size: 18).frame(width: 20)
            }
            Text(tab.displayTitle).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, CrestSpacing.medium + leadingInset)
        .padding(.trailing, CrestSpacing.medium)
        .frame(maxHeight: .infinity)
        .browserTabResidency(isLoaded: loadedTabIDs?.contains(tab.id) ?? true)
    }

    private func rowHeight(_ row: BrowserFolderDragPreviewRow) -> CGFloat {
        if case .folder = row.content { return BrowserFolderDragPreviewLayout.height }
        return row.frame.height
    }
}
