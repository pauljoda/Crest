import SwiftUI

/// One hover boundary for a folder's header and all of its visible contents,
/// held the container padding in from every edge of the folder's surface.
struct BrowserFolderSectionSurface: ViewModifier {
    let color: BrandColor
    var intensity: Double = 0
    var textColorMode: SpaceTextColorMode = .automatic
    /// How many folders hold this one.
    var depth = 0
    var isExpanded = false
    var isSelected = false
    let folderID: UUID
    let reorder: BrowserSidebarReorderState
    private var isTargeted: Bool { reorder.isTargetedFolder(folderID) }

    @Environment(\.folderPreviewShowsHighlight) private var previewShowsHighlight
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults)
    private var tabScale = 1.0
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BrowserFolderAppearancePreference.highlightModeKey, store: BrowserFolderAppearancePreference.defaults)
    private var highlightMode = BrowserFolderAppearancePreference.defaultHighlightMode
    @AppStorage(BrowserFolderAppearancePreference.showsBordersKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsBorders = true

    private var keepsHighlight: Bool { highlightMode.showsHighlight(isExpanded: isExpanded) }

    func body(content: Content) -> some View {
        content
            .padding(.top, BrowserSidebarMetrics.containerPadding)
            .padding(.bottom, BrowserSidebarMetrics.containerBottomPadding(tabScale: tabScale))
            .contentShape(.rect)
            .modifier(
                BrowserFolderHighlightSurface(
                    color: color, intensity: intensity,
                    textColorMode: textColorMode,
                    showsFill: keepsHighlight || previewShowsHighlight || isHovered || isSelected || isTargeted,
                    showsBorders: showsBorders, depth: depth,
                    isSelected: isSelected,
                    emphasisOpacity: keepsHighlight && (isHovered || isTargeted) ? (isTargeted ? 0.16 : 0.08) : 0)
            )
            .onHover { isHovered = $0 }
            .animation(
                CrestMotion.surface.unlessReducingMotion(reduceMotion),
                value: isHovered || isTargeted || isSelected
            )
    }
}
