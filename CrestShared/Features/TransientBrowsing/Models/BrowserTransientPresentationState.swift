import SwiftUI

/// Everything a transient overlay's surface needs to draw one frame of itself.
///
/// The shell owns the state that changes — whether the card has appeared, how
/// far a thumb has dragged it, what the person's accessibility settings ask
/// for — and hands it over as a value. The derivations below are the same on
/// every shell; the arrangement decides which of them are live and which
/// resolve to identity, so both shells run one chain rather than two.
struct BrowserTransientPresentationState {
    let arrangement: BrowserTransientCardArrangement
    /// Width the shell's own leading chrome has already claimed. Zero wherever
    /// the overlay owns the whole screen.
    var reservedLeadingWidth: CGFloat = 0
    var layoutDirection: LayoutDirection = .leftToRight
    /// How far a thumb has pushed the card down. Zero wherever the arrangement
    /// has no drag dismissal.
    var dismissalOffset: CGFloat = 0
    let isCardVisible: Bool
    let isCardExpanded: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    /// Staged only where a press can hold an overlay open before committing to
    /// it. A shell without that gesture is always committed.
    var presentationPhase: BrowserPeekPresentationPhase = .committed
    let sourcePresentation: BrowserPeekSourcePresentation

    var sourceTransform: BrowserTransientSourceTransform {
        BrowserTransientCardLayout.sourceCardTransform(for: sourcePresentation)
    }

    // MARK: - Growing out of the source link

    /// The entrance scale, applied to whichever layer the arrangement grows.
    /// The other layer is handed identity, so both shells run the same chain.
    func scale(for target: BrowserTransientEntranceTarget) -> CGSize {
        guard arrangement.entranceTarget == target else {
            return CGSize(width: 1, height: 1)
        }
        return CGSize(width: cardScaleX, height: cardScaleY)
    }

    func opacity(for target: BrowserTransientEntranceTarget) -> Double {
        arrangement.entranceTarget == target ? cardOpacity : 1
    }

    var controlsOpacity: Double {
        isCardExpanded ? 1 : 0
    }

    // MARK: - Being pushed away

    /// How far the card follows a thumb, honouring reduced motion. Identity
    /// wherever the arrangement has no drag dismissal.
    var dragOffset: CGFloat {
        BrowserVisualAccessibilityPolicy.spatialOffset(
            dismissalOffset,
            reduceMotion: reduceMotion
        )
    }

    /// The slight shrink that reads as the card receding under a drag.
    var dragScale: CGFloat {
        BrowserVisualAccessibilityPolicy.spatialScale(
            1 - min(dismissalOffset / 4_000, 0.045),
            reduceMotion: reduceMotion
        )
    }

    // MARK: - The scrim behind it

    /// The scrim fades out as the card is thrown away, and rests dimmer while
    /// the overlay is only staged behind a press.
    var scrimOpacity: Double {
        let progress = min(Double(dismissalOffset / 280), 1)
        let restingOpacity = presentationPhase == .staged ? 0.08 : 0.34
        return BrowserVisualAccessibilityPolicy.scrimOpacity(
            restingOpacity * (1 - progress) * (isCardVisible ? 1 : 0),
            reduceTransparency: reduceTransparency
        )
    }

    // MARK: - Derivations behind the entrance

    private var cardOpacity: Double {
        isCardExpanded || isCardVisible ? 1 : 0
    }

    private var cardScaleX: CGFloat {
        cardScale(
            visible: sourceTransform.scaleX,
            staged: sourceTransform.scaleX * 0.82
        )
    }

    private var cardScaleY: CGFloat {
        cardScale(
            visible: sourceTransform.scaleY,
            staged: sourceTransform.scaleY * 0.82
        )
    }

    /// A card that has finished growing is at its own size. Before that it is
    /// the size of the link it came from, or smaller again while it waits
    /// behind a press that has not committed.
    private func cardScale(visible: CGFloat, staged: CGFloat) -> CGFloat {
        guard !isCardExpanded else { return 1 }
        return BrowserVisualAccessibilityPolicy.spatialScale(
            isCardVisible ? visible : staged,
            reduceMotion: reduceMotion
        )
    }
}
