import SwiftUI

/// One hover boundary for a folder's header and all of its visible contents.
struct BrowserFolderSectionSurface: ViewModifier {
    let color: Color
    var leadingInset: CGFloat = CrestSpacing.small
    var hasVisibleContents = false
    let folderID: FolderID
    let reorder: BrowserSidebarReorderState
    private var isTargeted: Bool { reorder.isTargetedFolder(folderID) }

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(.bottom, hasVisibleContents ? CrestSpacing.small : 0)
            .contentShape(.rect)
            .background {
                if isHovered || isTargeted {
                    RoundedRectangle(cornerRadius: CrestLayout.sidebarControlCornerRadius, style: .continuous)
                        .fill(reduceTransparency ? color.opacity(0.28) : color.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: CrestLayout.sidebarControlCornerRadius, style: .continuous)
                                .strokeBorder(color.opacity(0.28), lineWidth: 0.5)
                        }
                        .padding(.leading, leadingInset)
                        .padding(.trailing, CrestSpacing.small)
                }
            }
            .onHover { isHovered = $0 }
            .animation(
                BrowserVisualAccessibilityPolicy.animation(CrestMotion.surface, reduceMotion: reduceMotion),
                value: isHovered || isTargeted
            )
    }
}
