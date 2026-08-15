import SwiftUI

extension View {
    func mobileFolderHeaderLayout(depth: Int) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(
                .leading,
                MobileSidebarRowLayoutPolicy.folderLeadingInset(depth: depth)
            )
            .padding(.trailing, 18)
            .frame(minHeight: CrestLayout.sidebarRowHeight)
    }
}
