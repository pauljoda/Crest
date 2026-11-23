import CoreGraphics

enum BrowserFolderDragPreviewLayout {
    static let height = BrowserTabDragPreviewLayout.rowSize.height
    /// How strongly the lifted folder's surface, its edge and its artwork
    /// wear the folder's color.
    static let tintOpacity = 0.12
    static let edgeOpacity = 0.35
    static let artworkOpacity = 0.86

    static func width(for sourceWidth: CGFloat) -> CGFloat {
        BrowserTabDragPreviewLayout.resolvedRowWidth(sourceWidth)
    }

    static func rowWidth(forSourceWidth sourceWidth: CGFloat) -> CGFloat {
        BrowserTabDragPreviewLayout.rowWidth(forSourceWidth: sourceWidth)
    }
}
