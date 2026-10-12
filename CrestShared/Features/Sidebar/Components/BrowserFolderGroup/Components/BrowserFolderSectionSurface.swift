import SwiftUI

/// One hover boundary for a folder's header and all of its visible contents.
struct BrowserFolderSectionSurface: ViewModifier {
    let color: BrandColor
    var intensity: Double = 0
    var textColorMode: SpaceTextColorMode = .automatic
    var leadingInset: CGFloat = CrestSpacing.small
    var hasVisibleContents = false
    var isSelected = false
    let folderID: UUID
    let reorder: BrowserSidebarReorderState
    private var isTargeted: Bool { reorder.isTargetedFolder(folderID) }

    @Environment(\.folderPreviewShowsHighlight) private var previewShowsHighlight
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BrowserFolderAppearancePreference.alwaysVisibleKey, store: BrowserFolderAppearancePreference.defaults)
    private var alwaysVisible = false
    @AppStorage(BrowserFolderAppearancePreference.showsBordersKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsBorders = true

    func body(content: Content) -> some View {
        content
            .padding(.bottom, hasVisibleContents ? BrowserFolderLayout.regionInset : 0)
            .contentShape(.rect)
            .modifier(
                BrowserFolderHighlightSurface(
                    color: color, intensity: intensity,
                    textColorMode: textColorMode,
                    showsFill: alwaysVisible || previewShowsHighlight || isHovered || isSelected || isTargeted,
                    showsBorders: showsBorders, leadingInset: leadingInset,
                    isSelected: isSelected,
                    emphasisOpacity: alwaysVisible && (isHovered || isTargeted) ? (isTargeted ? 0.16 : 0.08) : 0)
            )
            .onHover { isHovered = $0 }
            .animation(
                CrestMotion.surface.unlessReducingMotion(reduceMotion),
                value: isHovered || isTargeted || isSelected
            )
    }
}
