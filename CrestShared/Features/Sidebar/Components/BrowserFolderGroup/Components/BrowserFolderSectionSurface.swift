import SwiftUI

/// One hover boundary for a folder's header and all of its visible contents,
/// held the container padding in from every edge of the folder's surface.
/// A header Tidy made deepens it while its archive control is hovered, so the
/// person sees every tab the control will archive.
struct BrowserFolderSectionSurface: ViewModifier {
    let color: BrandColor
    var intensity: Double = 0
    var textColorMode: SpaceTextColorMode = .automatic
    /// How many folders hold this one.
    var depth = 0
    var isSelected = false
    let folderID: UUID
    let reorder: BrowserSidebarReorderState
    private var isTargeted: Bool { reorder.isTargetedFolder(folderID) }

    @Environment(\.folderPreviewShowsHighlight) private var previewShowsHighlight
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }
    @State private var isHovered = false
    @State private var isArchiveHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var alwaysVisible: Bool { BrowserDeviceAppearanceStore.shared.foldersAlwaysVisible }
    private var showsBorders: Bool { BrowserDeviceAppearanceStore.shared.foldersShowBorders }

    func body(content: Content) -> some View {
        content
            .environment(\.folderArchiveControlIsHovered, $isArchiveHovered)
            .padding(.top, BrowserSidebarMetrics.containerPadding)
            .padding(.bottom, BrowserSidebarMetrics.containerBottomPadding(tabScale: tabScale))
            .contentShape(.rect)
            .modifier(
                BrowserFolderHighlightSurface(
                    color: color, intensity: intensity,
                    textColorMode: textColorMode,
                    showsFill: alwaysVisible || previewShowsHighlight || isHovered || isSelected || isTargeted
                        || isArchiveHovered,
                    showsBorders: showsBorders, depth: depth,
                    isSelected: isSelected,
                    emphasisOpacity: emphasisOpacity)
            )
            .onHover { isHovered = $0 }
            .animation(
                CrestMotion.surface.unlessReducingMotion(reduceMotion),
                value: isHovered || isTargeted || isSelected || isArchiveHovered
            )
    }

    /// The drop target's emphasis, which the archive control shares.
    private var emphasisOpacity: Double {
        if isArchiveHovered { return 0.16 }
        guard alwaysVisible else { return 0 }
        return isTargeted ? 0.16 : isHovered ? 0.08 : 0
    }
}

extension EnvironmentValues {
    /// Set by the folder's surface for a control inside it that acts on the
    /// whole folder, such as a Tidy header's archive control.
    @Entry var folderArchiveControlIsHovered: Binding<Bool>? = nil
}
