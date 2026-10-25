import SwiftUI

/// The sidebar's shared geometry, and the one place its layers take their
/// shape from.
///
/// A *layer* is anything drawn as a surface above the sidebar's base: the
/// address field, the extension strip, the pinned tiles, every tab row's
/// selection and hover, the New Tab row's hover, folders, Split Views, and the
/// drag previews lifted from them. Every top-level layer sits the same distance
/// from the sidebar's edges and has the same corners. A container — a folder or
/// a Split View — holds its rows the same padding in from every side, and each
/// layer inside it is cornered concentrically, one padding tighter per
/// container around it.
enum BrowserSidebarMetrics {
    // MARK: - Static Variables

    static let lockedSpaceBlurRadius: CGFloat = 12
    static let addressBottomInset: CGFloat = 1
    /// The one gap down the top of a Space: address field to extension strip,
    /// strip to pinned tabs, and address field to pinned tabs when there is no
    /// strip. The selected pin's glow slides under whichever layer is above.
    static let topSectionSpacing = CrestSpacing.small
    static let pinnedTabsBottomInset: CGFloat = 6

    /// How far every top-level layer sits from the sidebar's leading and
    /// trailing edges.
    static let layerInset = CrestSpacing.small

    /// How far a container holds what it contains in from its own edge, the
    /// same on all four sides for folders and Split Views alike. It is also the
    /// step each level of nesting moves in by.
    static let containerPadding = CrestSpacing.extraSmall

    /// The space a container keeps above and below itself, apart from the rows
    /// beside it.
    static let containerSpacing = CrestSpacing.extraExtraSmall

    /// The shortest a folder header gets, before the tab scale, when the
    /// folder spacing setting takes its slack away: the smallest pointer
    /// target a sidebar row keeps.
    static let compactFolderHeaderHeight: CGFloat = 24

    // MARK: - Actions - Containers

    /// The padding a container keeps under its last row. A row already keeps
    /// half its separation around its own surface, so the container gives that
    /// much less and the surface sits exactly `padding` from the edge, as it
    /// does at the sides.
    @MainActor
    static func containerBottomPadding(tabScale: Double, padding: CGFloat = containerPadding) -> CGFloat {
        let separation = BrowserSidebarDensity(tabScale).rowSeparation(
            hasBorders: BrowserDeviceAppearanceStore.shared.tabs.borders == .all)
        return max(0, padding - CGFloat(separation) / 2)
    }

    // MARK: - Actions - Folder Spacing

    /// The space a folder keeps above and below itself for a folder spacing
    /// setting of `setting` points, zero or less: ``containerSpacing``, less
    /// what the setting takes away, which comes from here first.
    static func folderSpacing(_ setting: Double) -> CGFloat {
        max(0, containerSpacing - folderTightening(setting))
    }

    /// The padding a folder holds its header and rows in from its top and
    /// bottom edges: ``containerPadding`` until the setting has taken all of
    /// ``folderSpacing(_:)``, then less.
    static func folderPadding(_ setting: Double) -> CGFloat {
        max(0, containerPadding - max(0, folderTightening(setting) - containerSpacing))
    }

    /// How much shorter than a row a folder header gets above and below its
    /// title once the setting has taken all of a folder's spacing and padding.
    static func folderHeaderTrim(_ setting: Double) -> CGFloat {
        max(0, folderTightening(setting) - containerSpacing - containerPadding)
    }

    /// The height of a folder header, the one place both the header and the
    /// drag previews lifted from it take it from: a row at the device's tab
    /// scale on a pointer or `touch` shell, less what the folder spacing
    /// setting trims, never below the smallest target a row keeps. Accessible
    /// text sizes never draw it smaller than the default scale.
    @MainActor
    static func folderHeaderHeight(touch: Bool, isAccessibilitySize: Bool = false) -> CGFloat {
        let appearance = BrowserDeviceAppearanceStore.shared
        let density = BrowserSidebarDensity(isAccessibilitySize ? max(1, appearance.tabScale) : appearance.tabScale)
        return max(
            density.rowHeight(base: compactFolderHeaderHeight, touch: touch),
            density.rowHeight(base: CrestLayout.sidebarRowHeight, touch: touch)
                - 2 * folderHeaderTrim(appearance.foldersSpacing))
    }

    /// The points the setting takes from each side of a folder; none for the
    /// usual spacing or a value that is not a number.
    private static func folderTightening(_ setting: Double) -> CGFloat {
        setting.isFinite ? CGFloat(max(0, -setting)) : 0
    }

    // MARK: - Actions - Corners

    /// The corner radius of a layer drawn inside `depth` containers, from the
    /// device's corner radius setting and the sidebar's current row height.
    @MainActor
    static func layerCornerRadius(depth: Int = 0) -> CGFloat {
        layerCornerRadius(
            depth: depth, userRadius: BrowserDeviceAppearanceStore.shared.sidebarCornerRadius,
            capsuleRadius: capsuleRadius(tabScale: BrowserDeviceAppearanceStore.shared.tabScale))
    }

    /// The corner radius of a layer drawn inside `depth` containers, for a
    /// corner radius setting of `userRadius`, at the default row height.
    static func layerCornerRadius(depth: Int, userRadius: Double) -> CGFloat {
        layerCornerRadius(depth: depth, userRadius: userRadius, capsuleRadius: capsuleRadius(tabScale: 1))
    }

    /// The corner radius of a layer drawn inside `depth` containers.
    ///
    /// A top-level layer wears the setting plus ``containerPadding``, so the
    /// rows a container holds can wear the setting itself and the two curves
    /// stay parallel; each level inward is ``containerPadding`` tighter. A
    /// setting below the padding grows the outer corner by no more than the
    /// setting, so Square stays square at every depth and the slider stays
    /// continuous. No corner grows past `capsuleRadius`, half a row's height:
    /// at Capsule a single row is a capsule, and a Split View or open folder,
    /// which a capsule's corners cannot fit, keeps exactly that quarter circle
    /// so it matches the capsules around it.
    static func layerCornerRadius(depth: Int, userRadius: Double, capsuleRadius: CGFloat) -> CGFloat {
        let setting = userRadius.isFinite ? max(CGFloat(userRadius), 0) : 0
        let outer = min(setting + min(setting, containerPadding), max(0, capsuleRadius))
        return max(0, outer - containerPadding * CGFloat(max(0, depth)))
    }

    /// Half the height of one sidebar row at `tabScale`: the radius of a
    /// capsule row, and the roundest any sidebar corner gets.
    static func capsuleRadius(tabScale: Double) -> CGFloat {
        #if os(iOS)
            let touch = true
        #else
            let touch = false
        #endif
        return BrowserSidebarDensity(tabScale).rowHeight(base: CrestLayout.sidebarRowHeight, touch: touch) / 2
    }
}

extension EnvironmentValues {
    /// How many containers — folders and Split Views — hold the layer being
    /// drawn. A list row sets it from where the core places the row, and a
    /// Split View adds one for its members.
    @Entry var sidebarLayerDepth = 0
}
