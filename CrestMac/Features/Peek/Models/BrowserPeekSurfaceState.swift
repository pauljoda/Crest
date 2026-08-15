import SwiftUI

@MainActor
struct BrowserPeekSurfaceState {
    let reservedLeadingWidth: CGFloat
    let layoutDirection: LayoutDirection
    let isCardVisible: Bool
    let isCardExpanded: Bool
    let isInitialWebContentRevealed: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let sourcePresentation: BrowserPeekSourcePresentation

    var sourceAnchor: UnitPoint {
        UnitPoint(
            x: sourcePresentation.normalizedTouchX,
            y: sourcePresentation.normalizedTouchY
        )
    }

    var cardScaleX: CGFloat {
        guard !isCardExpanded else { return 1 }
        return min(max(sourcePresentation.normalizedWidth, 0.06), 0.42)
    }

    var cardScaleY: CGFloat {
        guard !isCardExpanded else { return 1 }
        return min(max(sourcePresentation.normalizedHeight, 0.035), 0.24)
    }

    func showsInitialLoadingSurface(for page: BrowserPage?) -> Bool {
        guard let page else { return false }
        return !isInitialWebContentRevealed
            && page.navigationFailure == nil
            && page.webContentFailureMessage == nil
    }
}
