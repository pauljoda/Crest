import SwiftUI

extension EnvironmentValues {
    /// How far a row inside folders moves its icon and title in past where its
    /// surface puts them: see `BrowserFolderLayout.rowContentIndent(depth:)`.
    @Entry var sidebarRowContentIndent: CGFloat = 0
}

/// How far a saved folder and everything inside it step in per nesting level.
///
/// One formula, on every shell. Surfaces step in by the container padding
/// every folder and Split View holds its contents in by, so each layer sits
/// exactly that padding inside the container around it. What a folder holds
/// steps its icons and titles a further `contentIndent` past the folder's own,
/// so a folder's tabs and the folders inside it read as inside it whether or
/// not its surface is showing.
enum BrowserFolderLayout {
    static let nestingIndent = BrowserSidebarMetrics.containerPadding

    /// How far a folder's contents put their icons past the folder's own icon.
    static let contentIndent = CrestSpacing.large

    /// How far a folder's surface sits from the sidebar's leading edge: the
    /// layer inset every top-level layer keeps, plus one step per folder that
    /// holds it. A folder's bounds start at that edge however deep it is.
    static func surfaceLeadingInset(depth: Int) -> CGFloat {
        BrowserSidebarMetrics.layerInset + nestingIndent * CGFloat(max(0, depth))
    }

    /// How far a row *inside* a folder sits from the sidebar's leading edge:
    /// one step for the folder itself, plus one per level above it. Tab rows
    /// and stacked split-group rows share it so a group never breaks the
    /// nesting rhythm.
    static func rowLeadingInset(depth: Int) -> CGFloat {
        nestingIndent * CGFloat(max(0, depth) + 1)
    }

    /// How far the folder header's own content sits from the leading edge of
    /// the space the folder's padding leaves.
    ///
    /// The base is the tab row's `contentLeadingInset` rather than a number of
    /// its own, so a top-level folder's icon keeps the tab rows' column, the
    /// same reason a split group's header reads its leading inset from the tab
    /// row profile. Each folder around it moves it one `contentIndent` on,
    /// into the column of the tabs beside it.
    static func headerLeadingInset(
        depth: Int,
        tabRowMetrics: BrowserSidebarTabRowMetrics
    ) -> CGFloat {
        tabRowMetrics.contentLeadingInset
            + contentIndent * CGFloat(max(0, depth))
    }

    /// The height of a folder's header beside rows of `rowHeight`: what is
    /// left once the padding and spacing a folder keeps around itself are
    /// taken off, so a closed folder stands exactly as tall as a tab row. It
    /// never gets shorter than `minimum`, the column its symbol takes.
    @MainActor
    static func headerHeight(rowHeight: CGFloat, tabScale: Double, minimum: CGFloat) -> CGFloat {
        let chrome =
            BrowserSidebarMetrics.containerPadding + BrowserSidebarMetrics.containerBottomPadding(tabScale: tabScale)
            + BrowserSidebarMetrics.containerSpacing * 2
        return max(rowHeight - chrome, minimum)
    }

    /// How far a folder's header reaches past its own edges for a finger: into
    /// the padding and spacing above it, which is the most a folder keeps on
    /// any side, so with the header's height a touch target is a whole row.
    static let headerTouchReach = BrowserSidebarMetrics.containerPadding + BrowserSidebarMetrics.containerSpacing

    /// How far a row inside `depth` folders moves its icon and title in past
    /// where its surface puts them, so they stand one `contentIndent` past
    /// the icon of the folder that holds the row.
    ///
    /// The row's surface already sits one `nestingIndent` in per folder, and
    /// a folder's header sits one more inside its own surface; the content
    /// makes up the rest.
    static func rowContentIndent(depth: Int) -> CGFloat {
        guard depth > 0 else { return 0 }
        return contentIndent * CGFloat(depth) - nestingIndent * CGFloat(depth - 1)
    }
}
