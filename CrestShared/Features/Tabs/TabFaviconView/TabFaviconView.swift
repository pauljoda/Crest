import SwiftUI

struct TabFaviconView: View {
    let subject: BrowserTabFaviconSubject
    var profileID: UUID? = nil
    var size: CGFloat = TabFaviconMetrics.defaultSize

    @State private var renderState = BrowserFaviconRenderState()
    @Environment(\.browserSpaceContentIsLocked) private var isLocked

    init(subject: BrowserTabFaviconSubject, profileID: UUID? = nil, size: CGFloat = TabFaviconMetrics.defaultSize) {
        self.subject = subject
        self.profileID = profileID
        self.size = size
    }

    var body: some View {
        let request = subject.renderRequest(
            profileID: profileID, maximumPixelSize: TabFaviconMetrics.maximumDecodedPixelSize(for: size),
            isUnlocked: !isLocked)
        TabFaviconContent(
            subject: subject,
            size: size,
            requestIdentity: request.identity,
            renderedImage: shownImage(for: request)
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: request.identity) {
            await loadRenderedImage(for: request)
        }
    }

    /// The icon this view renders for `request`, or the one an icon view
    /// drew before for the same image while this one renders its own.
    private func shownImage(for request: BrowserFaviconRenderRequest) -> BrowserFaviconRenderedImage? {
        if renderState.renderedImage?.image(matching: request.identity) != nil { return renderState.renderedImage }
        return BrowserFaviconShownImages.shared.image(for: request).map {
            BrowserFaviconRenderedImage(requestIdentity: request.identity, image: $0)
        }
    }

    private func loadRenderedImage(for request: BrowserFaviconRenderRequest) async {
        guard !Task.isCancelled else { return }
        renderState.begin(request.identity, isCancelled: Task.isCancelled)
        // An icon drawn before is already on screen. The view keeps it as its
        // own, so it still draws it after the shared images let it go.
        if let shown = BrowserFaviconShownImages.shared.image(for: request) {
            renderState.publish(shown, for: request.identity, isCancelled: Task.isCancelled)
            return
        }
        guard !Task.isCancelled else { return }
        guard let image = await BrowserFaviconRenderLoader.decode(request),
            !Task.isCancelled
        else { return }
        let rendered = Image(decorative: image, scale: TabFaviconMetrics.renderedImageScale)
        BrowserFaviconShownImages.shared.keep(rendered, for: request)
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
