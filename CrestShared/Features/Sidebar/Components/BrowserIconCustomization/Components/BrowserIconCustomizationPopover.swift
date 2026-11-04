import SwiftUI

extension View {
    func browserIconCustomizationPopover(
        _ presentation: BrowserIconCustomizationPresentation,
        arrowEdge: Edge? = .trailing
    ) -> some View {
        modifier(
            BrowserIconCustomizationPopoverModifier(
                presentation: presentation,
                arrowEdge: arrowEdge
            )
        )
    }
}

private struct BrowserIconCustomizationPopoverModifier: ViewModifier {
    let presentation: BrowserIconCustomizationPresentation
    let arrowEdge: Edge?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.crestPopover(isPresented: presentation.isPresented, arrowEdge: preferredArrowEdge) {
            popoverContent
        }
    }

    /// Compact windows let the system choose an edge that fits the picker.
    private var preferredArrowEdge: Edge? {
        horizontalSizeClass == .compact ? nil : arrowEdge
    }

    private var popoverContent: some View {
        BrowserIconCustomizationView(
            title: presentation.title,
            currentEmoji: presentation.currentEmoji,
            currentSystemSymbol: presentation.currentSystemSymbol,
            showsReset: presentation.showsReset,
            resetTitle: presentation.resetTitle,
            setEmoji: presentation.setEmoji,
            setSystemSymbol: presentation.setSystemSymbol,
            reset: presentation.reset
        )
        .presentationCompactAdaptation(.popover)
    }
}
