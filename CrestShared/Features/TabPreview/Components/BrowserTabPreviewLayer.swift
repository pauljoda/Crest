import SwiftUI

extension EnvironmentValues {
    /// Whether the app's windows draw a tab's preview card when the pointer
    /// rests on it, so its settings offer to turn previews off.
    @Entry var browserHostsTabPreviews = false
}

// MARK: - Types

/// Where a card sits beside its tab's row, in the layer.
struct BrowserTabPreviewPlacement {
    /// The card's top-left corner.
    let origin: CGSize
    /// The point at the card's edge, beside the row's middle, that the card
    /// grows from, in the card's points.
    let anchor: CGPoint
}

/// Draws the card of the tab or folder a window's sidebar is rested on,
/// beside its row or tile and over the page, inside the window, and beside a
/// folder's card, the card of a tab that card lists.
///
/// A shell lays the layer over its whole window, above the sidebar and the
/// page, tells it where the sidebar's page edge is, and hands it the
/// pictures it keeps. A card a finger held its row for shows over a scrim,
/// as a Peek does, which a tap takes down.
struct BrowserTabPreviewLayer: View {
    // MARK: - Static Variables

    /// How dark the ground under a held card is, as under a Peek.
    private static let heldScrimOpacity = 0.34

    // MARK: - Variables

    let preview: BrowserTabPreviewState
    /// How far the sidebar's page edge is from the side of the window the
    /// sidebar is on, or nil to place cards beside their rows alone.
    let sidebarEdge: CGFloat?
    /// The picture Crest kept of a tab's page, if it kept one.
    let picture: (UUID) -> BrowserTabPreviewPicture?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Actions - Presentation

    var body: some View {
        GeometryReader { proxy in
            let bounds = proxy.frame(in: .global)
            let opensTrailing = preview.shown.map { $0.frame.midX - bounds.minX < bounds.width / 2 } ?? true
            ZStack(alignment: .topLeading) {
                if preview.shown?.isHeldByTouch == true {
                    BrowserTransientScrim(
                        opacity: Self.heldScrimOpacity.scrimOpacity(reduceTransparency: reduceTransparency),
                        allowsDismissal: true, fadesIn: true, dismiss: preview.dismiss
                    )
                    .transition(.opacity.animation(CrestMotion.hover))
                }
                BrowserTabPreviewCardSlot(
                    preview: preview, bounds: bounds, opensTrailing: opensTrailing,
                    edge: sidebarEdge.map { opensTrailing ? $0 : bounds.width - $0 }, picture: picture)
                if case .folder = preview.shown?.subject {
                    BrowserTabPreviewCardSlot(
                        preview: preview.inner, bounds: bounds, opensTrailing: opensTrailing,
                        edge: preview.cardFrame.map { opensTrailing ? $0.maxX - bounds.minX : $0.minX - bounds.minX },
                        picture: picture)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// One preview's card, against `edge` beside its row, on the side the
/// layer chose, kept inside the window.
///
/// It grows out of the row as it fades in, or only fades in with Reduce
/// Motion; it moves to another row at once, and fades out.
private struct BrowserTabPreviewCardSlot: View {
    // MARK: - Static Variables

    /// The space between the sidebar, or the row, and the card.
    private static let gap: CGFloat = 8
    /// The closest the card comes to the window's edge.
    private static let margin: CGFloat = 8
    /// How far above the row's top the card's top sits, so the card's title
    /// lines up with the row's.
    private static let rise: CGFloat = 6
    /// The size a card is placed by before the first one is measured.
    private static let estimatedCardSize = CGSize(width: BrowserTabPreviewSurface.width, height: 220)
    /// The widest a held card grows across a narrow window.
    private static let heldMaximumWidth: CGFloat = 360
    /// How the card grows out of its row.
    private static let opening = Spring(duration: 0.3, bounce: 0.12)

    // MARK: - Variables

    let preview: BrowserTabPreviewState
    /// The layer's frame in the window.
    let bounds: CGRect
    /// Whether the card opens rightward, from a sidebar on its left.
    let opensTrailing: Bool
    /// Where the card's near edge leans, in the layer, or nil to lean on the
    /// row's own edge.
    let edge: CGFloat?
    let picture: (UUID) -> BrowserTabPreviewPicture?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardSize = Self.estimatedCardSize

    // MARK: - Actions - Presentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target = preview.shown {
                let placement = placement(of: target)
                card(for: target)
                    .environment(\.browserTabPreviewOpeningTime, openingTime)
                    .environment(\.browserTabPreviewCardWidth, width(of: target))
                    // A held card leaves the keyboard down until its search
                    // is tapped, where the keyboard would cover it.
                    .environment(\.browserTabPreviewTakesKeyboard, !target.isHeldByTouch)
                    .onGeometryChange(for: CGSize.self) {
                        $0.size
                    } action: {
                        cardSize = $0
                    }
                    .onHover { preview.pointerInCardChanged($0) }
                    .onChange(of: frame(of: placement), initial: true) { _, frame in
                        preview.cardFrame = frame
                    }
                    .offset(placement.origin)
                    .transition(transition(from: placement))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(CrestMotion.hover.unlessReducingMotion(reduceMotion), value: preview.shown == nil)
        .onAppear { preview.hostChanged(true) }
        .onDisappear { preview.hostChanged(false) }
    }

    /// How long the card takes to settle once it shows: the time its
    /// opening takes, or none where it only fades in.
    private var openingTime: Duration {
        reduceMotion ? .zero : .seconds(Self.opening.settlingDuration)
    }

    /// The tab's card, or the folder's.
    @ViewBuilder
    private func card(for target: BrowserTabPreviewTarget) -> some View {
        switch target.subject {
        case .tab(let tab):
            BrowserTabPreviewCard(tab: tab, context: target.context, picture: picture(tab.id))
        case .folder(let folder):
            BrowserFolderPreviewCard(
                folder: folder, context: target.context, preview: preview, menu: target.folderMenu)
        }
    }

    /// How wide `target`'s card is: every card's width, or across a narrow
    /// window as much as it leaves, for a held one.
    private func width(of target: BrowserTabPreviewTarget) -> CGFloat {
        guard target.isHeldByTouch else { return BrowserTabPreviewSurface.width }
        return min(Self.heldMaximumWidth, bounds.width - Self.margin * 2)
    }

    /// Where `target`'s card sits in the layer: beside its row, or below or
    /// above it for a held one.
    private func placement(of target: BrowserTabPreviewTarget) -> BrowserTabPreviewPlacement {
        target.isHeldByTouch ? heldPlacement(of: target.frame) : placement(of: target.frame)
    }

    /// Where a held card sits in the layer: centred on `row`, below it where
    /// it fits and above it where it doesn't, inside the layer, growing from
    /// the row's edge it leans on.
    private func heldPlacement(of row: CGRect) -> BrowserTabPreviewPlacement {
        let row = row.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let fitsBelow = row.maxY + Self.gap + cardSize.height + Self.margin <= bounds.height
        let x = row.midX - cardSize.width / 2
        let y = fitsBelow ? row.maxY + Self.gap : row.minY - Self.gap - cardSize.height
        let origin = CGSize(
            width: min(max(x, Self.margin), max(bounds.width - cardSize.width - Self.margin, Self.margin)),
            height: min(max(y, Self.margin), max(bounds.height - cardSize.height - Self.margin, Self.margin)))
        let middle = min(max(row.midX - origin.width, 0), cardSize.width)
        return BrowserTabPreviewPlacement(
            origin: origin, anchor: CGPoint(x: middle, y: fitsBelow ? 0 : cardSize.height))
    }

    /// Where the card sits in the layer: against `edge` beside `row`, at the
    /// row's height, inside the layer.
    private func placement(of row: CGRect) -> BrowserTabPreviewPlacement {
        let row = row.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let lean = edge ?? (opensTrailing ? row.maxX : row.minX)
        let x = opensTrailing ? lean + Self.gap : lean - Self.gap - cardSize.width
        let y = row.minY - Self.rise
        let origin = CGSize(
            width: min(max(x, Self.margin), max(bounds.width - cardSize.width - Self.margin, Self.margin)),
            height: min(max(y, Self.margin), max(bounds.height - cardSize.height - Self.margin, Self.margin)))
        let middle = min(max(row.midY - origin.height, 0), cardSize.height)
        return BrowserTabPreviewPlacement(
            origin: origin, anchor: CGPoint(x: opensTrailing ? 0 : cardSize.width, y: middle))
    }

    /// Where a card at `placement` is in the window.
    private func frame(of placement: BrowserTabPreviewPlacement) -> CGRect {
        CGRect(
            origin: CGPoint(x: bounds.minX + placement.origin.width, y: bounds.minY + placement.origin.height),
            size: cardSize)
    }

    /// The card grows out of its row as it fades in, or only fades in with
    /// Reduce Motion, and fades out.
    private func transition(from placement: BrowserTabPreviewPlacement) -> AnyTransition {
        let fade = AnyTransition.opacity.animation(CrestMotion.hover)
        guard !reduceMotion else { return fade }
        let growth = AnyTransition.modifier(
            active: BrowserTabPreviewGrowth(progress: 0, anchor: placement.anchor, origin: placement.origin),
            identity: BrowserTabPreviewGrowth(progress: 1, anchor: placement.anchor, origin: placement.origin))
        return .asymmetric(insertion: growth.combined(with: .opacity).animation(.spring(Self.opening)), removal: fade)
    }
}

extension EnvironmentValues {
    /// How long a preview card takes to settle once it shows. A text field
    /// that takes the keyboard while its card still grows draws its text
    /// above its middle, so a card's search waits this out first.
    @Entry var browserTabPreviewOpeningTime: Duration = .zero
}

extension EnvironmentValues {
    /// How wide a preview card is drawn.
    @Entry var browserTabPreviewCardWidth: CGFloat = BrowserTabPreviewSurface.width
    /// Whether a preview card's search takes the keyboard once the card has
    /// grown, as it does where the pointer or the keyboard brought the card.
    @Entry var browserTabPreviewTakesKeyboard = true
}
