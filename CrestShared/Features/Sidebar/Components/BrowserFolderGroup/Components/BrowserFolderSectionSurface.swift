import SwiftUI

/// One hover boundary for a folder's header and all of its visible contents.
struct BrowserFolderSectionSurface: ViewModifier {
    let color: BrowserSpaceBrandColor
    var intensity: Double = 0
    var textColorMode: BrowserSpaceTextColorMode = .automatic
    var leadingInset: CGFloat = CrestSpacing.small
    var hasVisibleContents = false
    var isSelected = false
    let folderID: FolderID
    let reorder: BrowserSidebarReorderState
    private var isTargeted: Bool { reorder.isTargetedFolder(folderID) }

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BrowserFolderAppearancePreference.alwaysVisibleKey, store: BrowserFolderAppearancePreference.defaults)
    private var alwaysVisible = false
    @AppStorage(BrowserFolderAppearancePreference.showsBordersKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsBorders = true

    func body(content: Content) -> some View {
        content
            .padding(.bottom, hasVisibleContents ? BrowserFolderAppearancePolicy.regionInset : 0)
            .contentShape(.rect)
            .modifier(
                BrowserFolderHighlightSurface(
                    color: color, intensity: intensity,
                    textColorMode: textColorMode,
                    showsFill: BrowserFolderAppearancePolicy.showsFill(
                        alwaysVisible: alwaysVisible, isHovered: isHovered || isSelected, isTargeted: isTargeted),
                    showsBorders: showsBorders, leadingInset: leadingInset,
                    isSelected: isSelected,
                    emphasisOpacity: alwaysVisible && (isHovered || isTargeted) ? (isTargeted ? 0.16 : 0.08) : 0)
            )
            .onHover { isHovered = $0 }
            .animation(
                BrowserVisualAccessibilityPolicy.animation(CrestMotion.surface, reduceMotion: reduceMotion),
                value: isHovered || isTargeted || isSelected
            )
    }
}
