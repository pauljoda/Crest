import SwiftUI

/// The whole of a transient overlay below its lock: the scrim, and the card
/// standing on it.
///
/// The card grows out of the link it came from. Where that growth is applied
/// is the one thing the arrangement changes here — a pointer overlay grows the
/// page alone and leaves its controls in place, a touch overlay grows the card
/// and its controls together — and the state hands identity to whichever layer
/// is not growing, so both run the same chain.
struct BrowserTransientSurface<WebContent: View>: View {
    let state: BrowserTransientPresentationState
    let pageStatus: BrowserTransientPageStatus
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let vocabulary: BrowserTransientOverlayVocabulary
    let actions: BrowserTransientCardActions
    @ViewBuilder let webContent: () -> WebContent

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BrowserTransientScrim(
                    opacity: state.scrimOpacity,
                    allowsDismissal: state.arrangement.allowsScrimDismissal,
                    dismiss: actions.dismiss
                )
                BrowserTransientCardStack(
                    state: state,
                    pageStatus: pageStatus,
                    spaces: spaces,
                    selectedSpaceID: selectedSpaceID,
                    vocabulary: vocabulary,
                    availableSize: proxy.size,
                    safeAreaInsets: proxy.safeAreaInsets,
                    actions: actions,
                    webContent: webContent
                )
                .scaleEffect(
                    x: assemblyScale.width,
                    y: assemblyScale.height,
                    anchor: state.sourceTransform.anchor
                )
                .opacity(state.opacity(for: .assembly))
            }
        }
        .ignoresSafeArea(edges: state.arrangement.ignoredSafeAreaEdges)
    }

    private var assemblyScale: CGSize {
        state.scale(for: .assembly)
    }
}
