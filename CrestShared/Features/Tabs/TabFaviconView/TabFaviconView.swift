import SwiftUI

struct TabFaviconView: View {
    let subject: BrowserTabFaviconSubject
    var profileID: UUID? = nil
    var size: CGFloat = TabFaviconMetrics.defaultSize

    @Environment(\.browserSpaceContentIsLocked) private var isLocked
    /// Retains the last shown image for this view instance so evicting the
    /// shared cache does not drop an on-screen favicon back to the globe.
    @State private var retained = TabFaviconRetainedImage()

    init(subject: BrowserTabFaviconSubject, profileID: UUID? = nil, size: CGFloat = TabFaviconMetrics.defaultSize) {
        self.subject = subject
        self.profileID = profileID
        self.size = size
    }

    var body: some View {
        let request = subject.renderRequest(
            profileID: profileID, maximumPixelSize: TabFaviconMetrics.maximumDecodedPixelSize(for: size),
            isUnlocked: !isLocked)
        if let shown = resolvedSynchronousImage(for: request) {
            TabFaviconContent(
                subject: subject,
                size: size,
                requestIdentity: request.identity,
                renderedImage: BrowserFaviconRenderedImage(requestIdentity: request.identity, image: shown)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else if request.payload != nil || request.fallbackPageURL != nil {
            TabFaviconAsyncView(subject: subject, size: size, request: request, retained: retained)
        } else {
            TabFaviconContent(
                subject: subject,
                size: size,
                requestIdentity: request.identity,
                renderedImage: nil
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }

    private func resolvedSynchronousImage(for request: BrowserFaviconRenderRequest) -> Image? {
        if let shown = BrowserFaviconShownImages.shared.image(for: request) {
            retained.keep(shown, for: request.identity)
            return shown
        }
        if let kept = retained.image(for: request.identity) {
            return kept
        }
        if let cached = BrowserFaviconRenderLoader.cachedImage(for: request) {
            let rendered = Image(decorative: cached, scale: TabFaviconMetrics.renderedImageScale)
            BrowserFaviconShownImages.shared.keep(rendered, for: request)
            retained.keep(rendered, for: request.identity)
            return rendered
        }
        return nil
    }
}

/// Non-observable per-view holder that retains a decoded favicon across
/// shared-cache eviction without triggering state mutations during `body`.
@MainActor
private final class TabFaviconRetainedImage {
    private var identity: BrowserFaviconTaskIdentity?
    private var image: Image?

    func image(for identity: BrowserFaviconTaskIdentity) -> Image? {
        guard self.identity == identity else { return nil }
        return image
    }

    func keep(_ image: Image, for identity: BrowserFaviconTaskIdentity) {
        self.identity = identity
        self.image = image
    }
}

private struct TabFaviconAsyncView: View {
    let subject: BrowserTabFaviconSubject
    let size: CGFloat
    let request: BrowserFaviconRenderRequest
    let retained: TabFaviconRetainedImage

    @State private var renderState = BrowserFaviconRenderState()

    var body: some View {
        TabFaviconContent(
            subject: subject,
            size: size,
            requestIdentity: request.identity,
            renderedImage: renderState.renderedImage
                ?? retained.image(for: request.identity).map {
                    BrowserFaviconRenderedImage(requestIdentity: request.identity, image: $0)
                }
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
        if let shown = BrowserFaviconShownImages.shared.image(for: request) {
            retained.keep(shown, for: request.identity)
            renderState.publish(shown, for: request.identity, isCancelled: Task.isCancelled)
            return
        }
        guard !Task.isCancelled else { return }
        guard let image = await BrowserFaviconRenderLoader.decode(request),
            !Task.isCancelled
        else { return }
        let rendered = Image(decorative: image, scale: TabFaviconMetrics.renderedImageScale)
        BrowserFaviconShownImages.shared.keep(rendered, for: request)
        retained.keep(rendered, for: request.identity)
        renderState.publish(rendered, for: request.identity, isCancelled: Task.isCancelled)
    }
}

/// A tab of the read model's icon: the row reads its own tab's fields and
/// image slot, so a new icon redraws only this tab's icon.
struct TabStateFaviconView: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    var profileID: UUID? = nil
    var size: CGFloat = TabFaviconMetrics.defaultSize

    var body: some View {
        TabFaviconView(
            subject: BrowserTabFaviconSubject(tab: tab, image: favicons.icon(of: tab.id)), profileID: profileID,
            size: size)
    }
}
