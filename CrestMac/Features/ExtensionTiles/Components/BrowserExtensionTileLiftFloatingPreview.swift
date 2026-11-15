import SwiftUI

/// The pinned extension tile somebody is carrying, drawn at the pointer over
/// everything, in the window's own drag preview window.
///
/// A full-bleed layer in the browser window's coordinates, as a sidebar row's
/// lift is. The tile rises by the house lift scale about the point the pointer
/// took hold of, so that point stays under the cursor, and carries the drag
/// preview's surface and shadow. Only the landing animates: animating the
/// position while carried would make the tile lag the pointer. Let go, it
/// settles onto its slot with the sidebar's drag motion, then fades as the
/// tile shows there again.
struct BrowserExtensionTileLiftFloatingPreview: View {
    // MARK: - Types

    /// What the preview window draws for a carried tile.
    struct Content: Equatable {
        let lift: BrowserExtensionTileLiftState.Lift
        /// Passed in rather than read from the environment: the preview is
        /// hosted in a window of its own, which inherits nothing from the
        /// browser's.
        let reduceMotion: Bool

        /// An envelope in the window's top-left coordinates that holds the
        /// tile, risen and shadowed, from the pointer to its landing slot.
        var drawingBounds: CGRect {
            let size = lift.originFrame.size
            let carried = CGRect(origin: lift.origin, size: size)
            return carried.union(lift.landing?.frame ?? carried)
                .insetBy(dx: -size.width * (BrowserSidebarReorderVisuals.liftScale - 1) - 48, dy: -48)
        }
    }

    // MARK: - Static Variables

    private static let glyphSize: CGFloat = 16
    private static let cornerRadius: CGFloat = 7

    // MARK: - Variables

    let content: Content

    private var lift: BrowserExtensionTileLiftState.Lift { content.lift }
    private var isRevealing: Bool { lift.landing?.isRevealing == true }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            art
                .scaleEffect(scale, anchor: grabAnchor)
                .offset(x: position.x, y: position.y)
                .animation(
                    CrestMotion.dragSource.unlessReducingMotion(content.reduceMotion), value: lift.landing?.frame
                )
                .opacity(isRevealing ? 0 : 1)
                .animation(
                    Animation.easeOut(duration: BrowserExtensionTileLiftState.revealDuration)
                        .unlessReducingMotion(content.reduceMotion),
                    value: isRevealing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The window behind this is transparent and click-through; this makes
        // certain nothing in the preview claims a hit test of its own.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Actions - Presentation

    private var art: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return ZStack {
            CrestSurfaceLayer(shape: shape)
                .overlay { shape.strokeBorder(CrestColor.subtleBorder, lineWidth: 0.5) }
            Group {
                if let icon = lift.icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.glyphSize, height: Self.glyphSize)
        }
        .frame(width: lift.originFrame.width, height: lift.originFrame.height)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        .modifier(SurfaceToneAppearance())
    }

    private var position: CGPoint {
        lift.landing?.frame.origin ?? lift.origin
    }

    private var scale: CGFloat {
        guard lift.landing == nil else { return 1 }
        return BrowserSidebarReorderVisuals.liftScale.unlessReducingMotion(content.reduceMotion)
    }

    private var grabAnchor: UnitPoint {
        let size = lift.originFrame.size
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: lift.grabOffset.width / size.width, y: lift.grabOffset.height / size.height)
    }
}
