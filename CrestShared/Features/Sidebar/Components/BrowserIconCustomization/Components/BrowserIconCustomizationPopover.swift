import SwiftUI

enum BrowserIconPopoverPlacementPolicy {
    /// Compact windows let the system choose an edge that fits the picker.
    static func preferredArrowEdge(
        horizontalSizeClass: UserInterfaceSizeClass?,
        regularArrowEdge: Edge?
    ) -> Edge? {
        horizontalSizeClass == .compact ? nil : regularArrowEdge
    }
}

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

    @ViewBuilder
    func body(content: Content) -> some View {
        if let preferredArrowEdge =
            BrowserIconPopoverPlacementPolicy.preferredArrowEdge(
                horizontalSizeClass: horizontalSizeClass,
                regularArrowEdge: arrowEdge
            )
        {
            content.popover(
                isPresented: presentation.isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: preferredArrowEdge
            ) {
                popoverContent
            }
        } else {
            content.popover(
                isPresented: presentation.isPresented,
                attachmentAnchor: .rect(.bounds)
            ) {
                popoverContent
            }
        }
    }

    private var popoverContent: some View {
        BrowserIconCustomizationView(
            title: presentation.title,
            currentEmoji: presentation.currentEmoji,
            currentSystemSymbol: presentation.currentSystemSymbol,
            systemSymbols: presentation.systemSymbols,
            showsReset: presentation.showsReset,
            resetTitle: presentation.resetTitle,
            setEmoji: presentation.setEmoji,
            setSystemSymbol: presentation.setSystemSymbol,
            reset: presentation.reset
        )
        .presentationCompactAdaptation(.popover)
    }
}
