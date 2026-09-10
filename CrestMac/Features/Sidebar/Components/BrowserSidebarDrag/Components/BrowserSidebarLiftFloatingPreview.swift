import SwiftUI

/// The whole of what the drag preview window shows: one lifted row, drawn at the
/// pointer, over nothing.
///
/// A full-bleed layer rather than a view sized to the preview, because its host
/// is a window pinned to the browser window's own bounds: placing the preview by
/// its top-left inside that layer puts it exactly where the same lift would have
/// been drawn in the view tree, in the same global coordinates the drag already
/// reports.
///
/// The art is the sidebar's own drag art — a tab morphing between its row, the
/// pinned tile, and the page-shaped card; a folder row; a stack of split-group
/// member lines — so moving where a lift is drawn changed nothing about what it
/// looks like.
///
/// Everything it needs arrives as a value. It reads no drag state, resolves no
/// tab, and owns no window; the host observes the reorder state and hands the
/// result down, which is what keeps a preview drawn in a second window a
/// presentation of the one drag rather than a copy of it.
struct BrowserSidebarLiftFloatingPreview: View {
    let subject: BrowserSidebarLiftPreviewSubject
    let lift: BrowserSidebarFloatingLift
    /// Passed in rather than read from the environment: this view is hosted in a
    /// window of its own, which inherits nothing from the browser's.
    var reduceMotion = false
    var onLandingComplete: (UUID) -> Void = { _ in }
    var onLandingArrived: (UUID) -> Void = { _ in }
    var selectedTabID: TabID?
    var loadedTabIDs: Set<TabID> = []
    @State private var landedFrame: CGRect?
    @State private var previewOpacity = 1.0
    @State private var stackHasGathered = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            art
                .scaleEffect(
                    x: scale.width, y: scale.height,
                    anchor: UnitPoint(x: lift.anchorFraction.x, y: lift.anchorFraction.y)
                )
                .offset(x: -displayAnchor.width, y: -displayAnchor.height)
                .animation(
                    BrowserVisualAccessibilityPolicy.animation(CrestMotion.dragPreview, reduceMotion: reduceMotion),
                    value: lift.shape
                )
                .offset(x: displayPointer.x, y: displayPointer.y)
                .opacity(previewOpacity)
            if let message = lift.constraintMessage {
                Label(message, systemImage: "nosign")
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: 280, alignment: .leading)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    .offset(x: displayPointer.x + 12, y: displayPointer.y + lift.sourceSize.height + 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Only the shape settles. Animating the position as well would make the
        // preview lag the pointer, which is the one thing a lift must never do.
        // The window behind this is transparent and click-through; this makes
        // certain nothing in the preview claims a hit test of its own.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(
                BrowserVisualAccessibilityPolicy.animation(CrestMotion.dragSource, reduceMotion: reduceMotion)
            ) {
                stackHasGathered = true
            }
        }
        .onChange(of: lift.landing, initial: true) { _, landing in
            guard let landing else {
                landedFrame = nil
                previewOpacity = 1
                return
            }
            if landing.isRevealing {
                withAnimation(
                    BrowserVisualAccessibilityPolicy.animation(.easeOut(duration: 0.10), reduceMotion: reduceMotion),
                    completionCriteria: .removed
                ) {
                    previewOpacity = 0
                } completion: {
                    onLandingComplete(landing.id)
                }
                return
            }
            withAnimation(
                BrowserVisualAccessibilityPolicy.animation(CrestMotion.dragSource, reduceMotion: reduceMotion),
                completionCriteria: .removed
            ) {
                landedFrame = landing.frame
            } completion: {
                onLandingArrived(landing.id)
            }
        }
    }

    private var artSize: CGSize {
        if case .tab = subject {
            return lift.shape.size(rowWidth: rowWidth, pinnedSize: pinnedSize)
        }
        return CGSize(
            width: BrowserFolderDragPreviewLayout.width(for: rowWidth), height: max(lift.sourceSize.height, 1))
    }

    /// Resize layout rather than scaling glyphs to meet the destination. A
    /// source tile and a full sidebar row do not have the same measured width.
    private var rowWidth: CGFloat { landedFrame?.width ?? lift.rowWidth }
    private var pinnedSize: CGSize { landedFrame?.size ?? lift.pinnedTileSize }
    private var displayAnchor: CGSize {
        if case .selection = subject { return lift.grabOffset }
        return CGSize(width: lift.anchorFraction.x * artSize.width, height: lift.anchorFraction.y * artSize.height)
    }

    private var scale: CGSize {
        if case .selection = subject { return CGSize(width: 1, height: 1) }
        if let landedFrame {
            return CGSize(
                width: landedFrame.width / max(artSize.width, 1), height: landedFrame.height / max(artSize.height, 1))
        }
        let value = BrowserVisualAccessibilityPolicy.spatialScale(
            BrowserSidebarReorderVisuals.liftScale, reduceMotion: reduceMotion)
        return CGSize(width: value, height: value)
    }

    private var displayPointer: CGPoint {
        guard let landedFrame else { return lift.presentationPointer }
        if case .selection(let rows) = subject {
            let leadOffset = compactOffset(for: lift.item.id, in: rows)
            return CGPoint(
                x: landedFrame.minX + lift.grabOffset.width,
                y: landedFrame.minY + leadOffset + lift.grabOffset.height)
        }
        return CGPoint(
            x: landedFrame.minX + lift.anchorFraction.x * landedFrame.width,
            y: landedFrame.minY + lift.anchorFraction.y * landedFrame.height)
    }

    @ViewBuilder
    private var art: some View {
        switch subject {
        case .tab(let tab):
            BrowserTabDragPreview(
                tab: tab,
                profileID: lift.profileID,
                targetShape: lift.shape,
                progress: lift.progress,
                rowWidth: rowWidth,
                pinnedSize: pinnedSize,
                isSelected: tab.id == selectedTabID,
                isLoaded: loadedTabIDs.contains(tab.id)
            )
        case .folder(let folder, let rows):
            BrowserFolderDragPreview(
                folder: folder, rowWidth: rowWidth,
                sourceHeight: lift.sourceSize.height, rows: rows, profileID: lift.profileID,
                loadedTabIDs: loadedTabIDs)
        case .selection(let rows):
            selectionStack(rows)
        case .splitGroup(let members):
            BrowserSplitGroupDragPreview(
                members: members,
                profileID: lift.profileID,
                rowWidth: rowWidth
            )
        }
    }

    private func stackHeight(_ row: BrowserSidebarSelectionPreviewRow) -> CGFloat {
        if row.isSplit || row.folder != nil { return row.frame.height }
        return lift.shape == .pinnedTile ? pinnedSize.height : BrowserTabDragPreviewLayout.rowSize.height
    }

    private func compactOffset(for id: BrowserSidebarReorderItemID, in rows: [BrowserSidebarSelectionPreviewRow])
        -> CGFloat
    {
        rows.prefix { $0.id != id }.reduce(0) { $0 + stackHeight($1) }
    }

    private func selectionStack(_ rows: [BrowserSidebarSelectionPreviewRow]) -> some View {
        let lead = rows.first { $0.id == lift.item.id } ?? rows[0]
        let leadOffset = compactOffset(for: lead.id, in: rows)
        return ZStack(alignment: .topLeading) {
            ForEach(rows) { row in
                selectionRow(row)
                    .offset(
                        x: stackHasGathered || reduceMotion ? 0 : row.frame.minX - lead.frame.minX,
                        y: stackHasGathered || reduceMotion
                            ? compactOffset(for: row.id, in: rows) - leadOffset
                            : row.frame.minY - lead.frame.minY)
            }
        }
        .frame(width: rowWidth, height: lead.frame.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func selectionRow(_ row: BrowserSidebarSelectionPreviewRow) -> some View {
        if let folder = row.folder {
            BrowserFolderDragPreview(
                folder: folder, rowWidth: rowWidth, sourceHeight: row.frame.height,
                rows: row.folderRows, profileID: lift.profileID, loadedTabIDs: loadedTabIDs)
        } else if row.isSplit {
            BrowserSplitGroupDragPreview(
                members: row.tabs, profileID: lift.profileID, rowWidth: rowWidth,
                sourceHeight: row.frame.height, loadedTabIDs: loadedTabIDs)
        } else if let tab = row.tabs.first {
            BrowserTabDragPreview(
                tab: tab, profileID: lift.profileID,
                targetShape: lift.shape == .pinnedTile ? .pinnedTile : .row,
                progress: lift.shape == .pinnedTile ? 1 : 0,
                rowWidth: rowWidth, pinnedSize: pinnedSize,
                isSelected: tab.id == selectedTabID, isLoaded: loadedTabIDs.contains(tab.id))
        }
    }

}
