import SwiftUI

/// The layer a transient overlay grows out of its source link.
enum BrowserTransientEntranceTarget: Equatable, Sendable {
    /// Only the page grows; the controls stay put and fade in.
    case pageCard

    /// The card and its controls grow together as one assembly.
    case assembly
}

/// How a transient overlay places its card in the room the screen gives it.
///
/// Peek and Quick Window are one surface, but the room around that surface is
/// not the same everywhere. A pointer overlay stands inside a window whose
/// leading chrome the person can still see and reach, so it keeps clear of
/// that chrome and hangs its controls above the card. A handheld overlay owns
/// the whole screen, fills the safe area, and is pushed away with a thumb. A
/// large touch screen has the room to float a card at a fraction of its size
/// with the controls beneath it.
///
/// The arrangement names those three rooms so one surface can lay itself out
/// instead of asking which target compiled it. It is an explicit shell input
/// rather than a capability bit: what varies is how much room there is and how
/// the card is reached, not whether a shell can do something.
enum BrowserTransientCardArrangement: Equatable, Sendable {
    /// A card beside a window's reserved leading chrome, sized by the shared
    /// window geometry policy and dismissed with the pointer or a key.
    case pointer

    /// A card filling a handheld screen's safe area, dragged downwards to
    /// dismiss. Its scrim is under a thumb the whole time, so tapping it must
    /// not close anything.
    case sheet

    /// A card floating at a fraction of a large touch screen, with room left
    /// around it for the scrim to be a deliberate target.
    case canvas
}

// MARK: - Stacking the card, its controls, and the way out

extension BrowserTransientCardArrangement {
    var entranceTarget: BrowserTransientEntranceTarget {
        self == .pointer ? .pageCard : .assembly
    }

    /// Whether the controls sit above the card, as `BrowserPeekChromePolicy`
    /// describes for a pointer. Touch arrangements put them within reach of a
    /// thumb instead.
    var placesControlsAboveCard: Bool { self == .pointer }

    var controlAlignment: HorizontalAlignment {
        self == .sheet ? .center : .trailing
    }

    var controlSpacing: CGFloat { self == .sheet ? 8 : 10 }

    /// Whether the control bar may shrink below its natural width. A sheet's
    /// screen can be narrower than the bar, so there the bar is a maximum with
    /// its own padding; elsewhere it is a fixed width.
    var constrainsControlBarToMaximumWidth: Bool { self == .sheet }

    var controlBarPadding: CGFloat { self == .sheet ? 10 : 0 }

    var allowsScrimDismissal: Bool { self != .sheet }

    var allowsDragDismissal: Bool { self == .sheet }
}

// MARK: - Geometry

extension BrowserTransientCardArrangement {
    /// Safe-area edges the surface draws through. A pointer overlay is laid
    /// out against the window it reserves space inside, so it takes the whole
    /// window; touch arrangements respect the screen's insets.
    var ignoredSafeAreaEdges: Edge.Set { self == .pointer ? .all : [] }

    /// The region of the container the card is laid out inside, or `nil` where
    /// the card simply fills what it is given.
    func contentFrame(
        in containerSize: CGSize,
        reservedLeadingWidth: CGFloat,
        layoutDirection: LayoutDirection
    ) -> CGRect? {
        guard self == .pointer else { return nil }
        return BrowserPeekPresentationPolicy.desktopWebContentFrame(
            in: containerSize,
            reservedLeadingWidth: reservedLeadingWidth,
            layoutDirection: layoutDirection
        )
    }

    /// The card's own size inside that region, or `nil` where the card takes
    /// everything the stack leaves it.
    func cardSize(in contentSize: CGSize) -> CGSize? {
        switch self {
        case .pointer:
            BrowserPeekPresentationPolicy.desktopCardSize(in: contentSize)
        case .sheet:
            nil
        case .canvas:
            CGSize(
                width: min(max(contentSize.width * 0.76, 600), 1_180),
                height: min(max(contentSize.height * 0.78, 430), 820)
            )
        }
    }

    func contentInsets(safeAreaInsets: EdgeInsets) -> EdgeInsets {
        switch self {
        case .pointer:
            EdgeInsets(top: 30, leading: 30, bottom: 30, trailing: 30)
        case .sheet:
            BrowserTransientCardLayout.cardInsets(
                safeAreaInsets: safeAreaInsets,
                minimumHorizontal: 14,
                minimumVertical: 10
            )
        case .canvas:
            BrowserTransientCardLayout.cardInsets(
                safeAreaInsets: safeAreaInsets,
                minimumHorizontal: 28,
                minimumVertical: 28
            )
        }
    }
}

// MARK: - Card material

extension BrowserTransientCardArrangement {
    /// A thumb-sized card is held closer and rounded more heavily than one
    /// read at pointer distance.
    var cardCornerRadius: CGFloat { self == .sheet ? 24 : 15 }

    var cardBorderOpacity: Double { self == .pointer ? 0.16 : 0.18 }

    var cardShadowOpacity: Double { self == .pointer ? 0.34 : 0.32 }

    var cardShadowRadius: CGFloat { self == .pointer ? 28 : 24 }

    var cardShadowOffsetY: CGFloat { self == .pointer ? 14 : 12 }
}
