import SwiftUI

/// One hover boundary for a folder's header and all of its visible contents,
/// held the container padding in from every edge of the folder's surface. A
/// Split View wears it too, with no folder of its own to be dropped into. A
/// group follows the group appearance choices in place of the folder ones.
struct BrowserFolderSectionSurface: ViewModifier {
    let color: BrandColor
    var isGroup = false
    var intensity: Double = 0
    var textColorMode: SpaceTextColorMode = .automatic
    /// How many folders hold this one.
    var depth = 0
    var isSelected = false
    /// The folder a drop can file into, or nil for a container that takes
    /// none, such as a Split View.
    let folderID: UUID?
    let reorder: BrowserSidebarReorderState
    /// Whether the surface steps itself in from the sidebar's edges, as a
    /// folder's does; a Split View's row already stands in place.
    var insetsSurface = true
    private var isTargeted: Bool { folderID.map(reorder.isTargetedFolder) ?? false }

    @Environment(\.folderPreviewShowsHighlight) private var previewShowsHighlight
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var appearance: BrowserDeviceAppearanceStore { BrowserDeviceAppearanceStore.shared }
    private var alwaysVisible: Bool { isGroup ? appearance.groupsAlwaysVisible : appearance.foldersAlwaysVisible }
    private var showsBorders: Bool { isGroup ? appearance.groupsShowBorders : appearance.foldersShowBorders }

    func body(content: Content) -> some View {
        content
            .padding(.top, BrowserSidebarMetrics.containerPadding)
            .padding(.bottom, BrowserSidebarMetrics.containerBottomPadding)
            .contentShape(.rect)
            .modifier(
                BrowserFolderHighlightSurface(
                    color: color, intensity: intensity,
                    textColorMode: textColorMode,
                    showsFill: alwaysVisible || previewShowsHighlight || isHovered || isSelected || isTargeted,
                    showsBorders: showsBorders, depth: depth, insetsSurface: insetsSurface,
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
