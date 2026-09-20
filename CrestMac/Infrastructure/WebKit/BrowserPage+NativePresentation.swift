import AppKit
import WebKit

/// Native presentation operations used by Crest's existing views. Engine
/// objects and snapshot configuration stay behind the page boundary.
extension BrowserPage {
    var nativeView: NSView { pageEngine.nativeView }
    var presentationWindow: NSWindow? { nativeView.window }
    var viewportSize: CGSize { nativeView.bounds.size }

    var canReviewCertificate: Bool {
        BrowserSiteCertificatePresentationPolicy.isAvailable(
            url: displayURL,
            hasServerTrust: webKitView?.serverTrust != nil
        )
    }

    /// Capture the certificate and its window before dismissing a popover.
    /// A later navigation must not change which certificate the action reviews.
    func certificateReviewAction() -> (@MainActor () -> Void)? {
        guard let trust = webKitView?.serverTrust else { return nil }
        let window = presentationWindow
        return { BrowserSiteCertificatePresenter.present(trust: trust, for: window) }
    }

    func reviewCertificate() { certificateReviewAction()?() }

    /// Issue synchronously so drag pickup can request the current frame before
    /// changing its presentation. A missing image never reveals another page.
    func captureViewport(
        width: CGFloat? = nil,
        completion: @escaping @MainActor (NSImage?) -> Void
    ) {
        pageEngine.capture(rect: nil, width: width, completion: completion)
    }
}
