import SwiftUI

struct BrowserSidebarWidgetCard: View {
    let instance: BrowserSidebarWidgetInstance
    /// Zero identifies the active card; rear-card content fades with depth.
    let depth: Int
    /// Rear cards use the active card's height.
    let fixedHeight: CGFloat?
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void
    let activateMediaSession: (BrowserTabRuntimeAssignment) -> Void
    let ownerFaviconData: (BrowserTabRuntimeAssignment) -> Data?

    var body: some View {
        presentation
            .padding(CrestSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: fixedHeight, alignment: .top)
            .opacity(BrowserSidebarWidgetDeckStyle.contentOpacity(forDepth: depth))
            .modifier(BrowserSidebarWidgetCardContentFade(depth: depth))
            .clipShape(BrowserSidebarWidgetDeckStyle.cardShape)
            .modifier(BrowserSidebarWidgetCardChrome(depth: depth))
            .contentShape(BrowserSidebarWidgetDeckStyle.cardShape)
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var presentation: some View {
        switch instance.presentation {
        case .nowPlaying(let session):
            BrowserNowPlayingSidebarWidget(
                instance: instance,
                session: session,
                faviconData: ownerFaviconData(session.owner),
                perform: perform,
                activate: activateMediaSession
            )
        case .softwareUpdate(let update):
            BrowserSoftwareUpdateSidebarWidget(
                instance: instance,
                update: update,
                perform: perform
            )
        }
    }

}

/// Fades rear-card controls before the clipping edge.
private struct BrowserSidebarWidgetCardContentFade: ViewModifier {
    let depth: Int

    func body(content: Content) -> some View {
        if BrowserSidebarWidgetDeckStyle.masksContent(forDepth: depth) {
            content.mask { BrowserSidebarWidgetDeckStyle.contentMask }
        } else {
            content
        }
    }
}

/// A card is a layer of the device's material, as the pins and the address
/// field are, edged in Crest's warm hairline and casting a paper layer's
/// shadow.
private struct BrowserSidebarWidgetCardChrome: ViewModifier {
    let depth: Int

    func body(content: Content) -> some View {
        content
            .background { CrestSurfaceLayer(shape: BrowserSidebarWidgetDeckStyle.cardShape) }
            .overlay {
                BrowserSidebarWidgetDeckStyle.cardShape
                    .stroke(
                        CrestBrandTheme.line.opacity(chromeScale),
                        lineWidth: BrowserSidebarWidgetDeckStyle.cardStrokeWidth
                    )
                    .allowsHitTesting(false)
            }
            .crestElevation(.control, scale: chromeScale)
            .crestElevation(.card, scale: chromeScale)
    }

    private var chromeScale: Double {
        depth == 0 ? 1 : BrowserSidebarWidgetDeckStyle.underCardShadowScale
    }
}
