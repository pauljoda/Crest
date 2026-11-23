import SwiftUI

/// One hover boundary for a folder's header and all of its visible contents,
/// held the container padding in from every edge of the folder's surface. A
/// Split View wears it too, with no folder of its own to be dropped into. It
/// follows the appearance choices of the folder's kind.
struct BrowserFolderSectionSurface: ViewModifier {
    /// How strongly a folder a lifted item would drop into is lit, beyond
    /// a hover's wash.
    private static let targetedEmphasisOpacity = 0.16

    let color: BrandColor
    var kind = BrowserFolderKind.folder
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
    private var alwaysVisible: Bool { appearance[keyPath: kind.showsHighlights] }
    private var showsBorders: Bool { appearance[keyPath: kind.showsBorders] }
    /// The wash over a surface that always shows: a hover's, or a stronger
    /// one while a lifted item would drop into the folder.
    private var emphasisOpacity: Double {
        guard alwaysVisible, isHovered || isTargeted else { return 0 }
        return isTargeted ? Self.targetedEmphasisOpacity : CrestOpacity.hover
    }

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
                    emphasisOpacity: emphasisOpacity)
            )
            .onHover { isHovered = $0 }
            .animation(
                CrestMotion.surface.unlessReducingMotion(reduceMotion),
                value: isHovered || isTargeted || isSelected
            )
    }
}
