import UIKit

extension MobileBrowserTransientOverlayModel {
    // MARK: - Variables - Link Menu

    /// What a Peek's "…" offers for the page its card shows, as the system's
    /// menu does for a link. A Quick Window has no link menu.
    var linkMenu: BrowserPeekLinkMenu? {
        guard !request.isQuickWindow else { return nil }
        let items = [
            BrowserPeekLinkMenuItem(
                title: String(localized: "Open in New Tab"), systemImage: "plus.square.on.square"
            ) { [weak self] in
                guard let self else { return }
                promote(to: request.spaceAssignment)
            },
            BrowserPeekLinkMenuItem(title: String(localized: "Copy Link"), systemImage: "link") { [weak self] in
                BrowserPageLinkClipboard.copy(self?.linkURL)
            },
            BrowserPeekLinkMenuItem(title: String(localized: "Share…"), systemImage: "square.and.arrow.up") {
                [weak self] in
                guard let url = self?.linkURL else { return }
                MobileBrowserDialogPresenter.present(
                    UIActivityViewController(activityItems: [url], applicationActivities: nil), fallback: {})
            },
            BrowserPeekLinkMenuItem(
                title: String(localized: "Download Linked File"), systemImage: "arrow.down.circle"
            ) { [weak self] in
                guard let self, let url = linkURL else { return }
                page?.downloadLinkedFile(url)
            },
        ]
        return BrowserPeekLinkMenu(items: items, size: MobilePeekLinkMenuAnchor.size(for: items))
    }

    /// The address the card shows: its page's once it has one.
    private var linkURL: URL? {
        page?.live.displayURL ?? request.url
    }
}
