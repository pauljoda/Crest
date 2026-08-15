import SwiftUI

extension View {
    func savedFolderHeaderLayout(depth: Int) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 9 + CGFloat(depth) * 14)
            .padding(.trailing, 9)
            .frame(height: CrestLayout.sidebarRowHeight)
    }
}
