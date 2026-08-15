import SwiftUI

struct MobileBrowserTransientPresentationState {
    let dismissalOffset: CGFloat
    let isCardVisible: Bool
    let isCardExpanded: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let presentationPhase: BrowserPeekPresentationPhase
    let sourcePresentation: BrowserPeekSourcePresentation

    var sourceTransform: MobileBrowserPeekSourceTransform {
        MobileBrowserTransientLayout.sourceCardTransform(
            for: sourcePresentation
        )
    }

    var cardScaleX: CGFloat {
        cardScale(
            expanded: 1,
            visible: sourceTransform.scaleX,
            staged: sourceTransform.scaleX * 0.82
        )
    }

    var cardScaleY: CGFloat {
        cardScale(
            expanded: 1,
            visible: sourceTransform.scaleY,
            staged: sourceTransform.scaleY * 0.82
        )
    }

    var cardOpacity: Double {
        isCardExpanded ? 1 : (isCardVisible ? 1 : 0)
    }

    var controlsOpacity: Double {
        isCardExpanded ? 1 : 0
    }

    var scrimOpacity: Double {
        let progress = min(Double(dismissalOffset / 280), 1)
        let restingOpacity = presentationPhase == .staged ? 0.08 : 0.34
        return BrowserVisualAccessibilityPolicy.scrimOpacity(
            restingOpacity * (1 - progress) * (isCardVisible ? 1 : 0),
            reduceTransparency: reduceTransparency
        )
    }

    var phoneScale: CGFloat {
        BrowserVisualAccessibilityPolicy.spatialScale(
            1 - min(dismissalOffset / 4_000, 0.045),
            reduceMotion: reduceMotion
        )
    }

    private func cardScale(
        expanded: CGFloat,
        visible: CGFloat,
        staged: CGFloat
    ) -> CGFloat {
        guard !isCardExpanded else { return expanded }
        return BrowserVisualAccessibilityPolicy.spatialScale(
            isCardVisible ? visible : staged,
            reduceMotion: reduceMotion
        )
    }
}
