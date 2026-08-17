import SwiftUI

struct TabFaviconView: View {
    let tab: BrowserTab
    var profileID: UUID? = nil
    var size: CGFloat = TabFaviconMetrics.defaultSize

    @State private var renderState = BrowserFaviconRenderState()

    var body: some View {
        let request = BrowserFaviconTaskIdentityPolicy.renderRequest(
            for: tab,
            profileID: profileID,
            maximumPixelSize: TabFaviconMetrics.maximumDecodedPixelSize(for: size)
        )
        TabFaviconContent(
            tab: tab,
            size: size,
            requestIdentity: request.identity,
            renderedImage: renderState.renderedImage
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: request.identity) {
            await loadRenderedImage(for: request)
        }
    }

    private func loadRenderedImage(for request: BrowserFaviconRenderRequest) async {
        guard !Task.isCancelled else { return }
        renderState.begin(request.identity, isCancelled: Task.isCancelled)
        guard !Task.isCancelled else { return }
        guard let image = await BrowserFaviconRenderLoader.decode(request),
            !Task.isCancelled
        else { return }
        renderState.publish(
            Image(
                decorative: image,
                scale: TabFaviconMetrics.renderedImageScale
            ),
            for: request.identity,
            isCancelled: Task.isCancelled
        )
    }
}
