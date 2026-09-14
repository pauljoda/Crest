import CoreGraphics

/// What the window-level drag preview is drawing, if anything.
///
/// Two things in this app travel on the pointer and are clipped by everything if
/// the view tree draws them: a lifted sidebar row and a carried Split View card.
/// Both need the same thing — a transparent window ordered above the browser's,
/// so the page's `WKWebView` cannot composite over them — and neither needs one
/// of its own. This is the seam between them: one host, one panel, one lifetime,
/// and a case per kind of thing being carried.
///
/// Equatable so the host can tell a frame that changed something from a frame
/// that changed nothing, and skip the window work for the latter.
enum BrowserDragPreviewWindowContent: Equatable {
    case sidebarLift(BrowserSidebarLiftPreviewContent)
    case splitCardLift(BrowserSplitCardLiftPreviewContent)

    /// A conservative envelope in the source window's top-left coordinates.
    /// Cover both ends of a morph so resizing the native panel cannot clip the
    /// animation, including a selection gathering from its original row offsets.
    var drawingBounds: CGRect {
        switch self {
        case .sidebarLift(let sidebar):
            return sidebarDrawingBounds(sidebar)
        case .splitCardLift(let card):
            let scale = BrowserSidebarReorderVisuals.liftScale
            return CGRect(origin: card.origin, size: card.size)
                .insetBy(
                    dx: -card.size.width * (scale - 1) - 48,
                    dy: -card.size.height * (scale - 1) - 48)
        }
    }

    private func sidebarDrawingBounds(_ sidebar: BrowserSidebarLiftPreviewContent) -> CGRect {
        let lift = sidebar.lift
        let rowSize = BrowserTabDragPreviewLayout.rowSize
        var width = max(
            BrowserTabDragPreviewLayout.resolvedRowWidth(lift.rowWidth), lift.sourceSize.width,
            lift.pinnedTileSize.width, BrowserTabDragPreviewLayout.cardSize.width)
        var height = max(
            rowSize.height, lift.sourceSize.height, lift.pinnedTileSize.height,
            BrowserTabDragPreviewLayout.cardSize.height)

        switch sidebar.subject {
        case .selection(let rows):
            if let lead = rows.first(where: { $0.id == lift.item.id }) ?? rows.first {
                var gatheredHeight: CGFloat = 0
                for row in rows {
                    let rowWidth = max(
                        BrowserTabDragPreviewLayout.resolvedRowWidth(lift.rowWidth), row.frame.width,
                        lift.pinnedTileSize.width)
                    let rowHeight = max(
                        row.frame.height, rowSize.height, lift.pinnedTileSize.height,
                        row.isSplit ? CGFloat(row.tabs.count + 1) * rowSize.height : 0)
                    gatheredHeight += rowHeight
                    width = max(width, abs(row.frame.minX - lead.frame.minX) + rowWidth)
                    height = max(height, abs(row.frame.minY - lead.frame.minY) + rowHeight)
                }
                width += abs(lift.grabOffset.width)
                height = max(height, gatheredHeight) + abs(lift.grabOffset.height)
            }
        case .splitGroup(let tabs):
            height = max(height, CGFloat(tabs.count + 1) * rowSize.height)
        case .tab, .folder:
            break
        }

        let scale = BrowserSidebarReorderVisuals.liftScale
        let pointer = lift.presentationPointer
        let extent = CGSize(width: width * scale + 48, height: height * scale + 48)
        var bounds = CGRect(
            x: pointer.x - extent.width, y: pointer.y - extent.height,
            width: extent.width * 2, height: extent.height * 2)
        if let landing = lift.landing {
            bounds = bounds.union(landing.frame.insetBy(dx: -extent.width, dy: -extent.height))
        }
        if lift.constraintMessage != nil {
            // The short constraint label is at most 280 points wide. The
            // existing preview envelope leaves room for its wrapped caption.
            bounds = bounds.union(
                CGRect(
                    x: pointer.x + 12, y: pointer.y + lift.sourceSize.height + 12,
                    width: 280, height: extent.height))
        }
        return bounds
    }
}
