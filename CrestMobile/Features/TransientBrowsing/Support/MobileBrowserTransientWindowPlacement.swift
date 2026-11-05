import SwiftUI
import UIKit

/// Where a transient overlay sits in its window.
///
/// A page measures the link a Peek grows from against its window, but the
/// overlay covers only the page's part of it: above the bar on an iPhone, and
/// beside the sidebar on an iPad. The placement measures that link against
/// the overlay instead, so the card grows from where the link is.
struct MobileBrowserTransientWindowPlacement: Equatable {
    // MARK: - Variables

    /// The overlay's frame in its window.
    let frame: CGRect
    let windowSize: CGSize

    // MARK: - Actions - Placing

    /// `source`, measured against the window, measured against the overlay.
    func place(_ source: BrowserPeekSourcePresentation) -> BrowserPeekSourcePresentation {
        guard frame.width > 0, frame.height > 0 else { return source }
        let horizontal = windowSize.width / frame.width
        let vertical = windowSize.height / frame.height
        return BrowserPeekSourcePresentation(
            normalizedMinX: source.normalizedMinX * horizontal - frame.minX / frame.width,
            normalizedMinY: source.normalizedMinY * vertical - frame.minY / frame.height,
            normalizedWidth: source.normalizedWidth * horizontal,
            normalizedHeight: source.normalizedHeight * vertical,
            normalizedTouchX: source.normalizedTouchX * horizontal - frame.minX / frame.width,
            normalizedTouchY: source.normalizedTouchY * vertical - frame.minY / frame.height,
            label: source.label
        )
    }
}

extension MobileBrowserTransientWindowPlacement {
    /// Reports the placement of the view it backs each time it changes.
    struct Reader: UIViewRepresentable {
        let placementChanged: (MobileBrowserTransientWindowPlacement) -> Void

        func makeUIView(context: Context) -> ReaderView {
            let view = ReaderView()
            view.isUserInteractionEnabled = false
            return view
        }

        func updateUIView(_ view: ReaderView, context: Context) {
            view.placementChanged = placementChanged
        }

        final class ReaderView: UIView {
            var placementChanged: (MobileBrowserTransientWindowPlacement) -> Void = { _ in }
            private var placement: MobileBrowserTransientWindowPlacement?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                report()
            }

            override func layoutSubviews() {
                super.layoutSubviews()
                report()
            }

            private func report() {
                guard let window else { return }
                let placement = MobileBrowserTransientWindowPlacement(
                    frame: convert(bounds, to: window), windowSize: window.bounds.size)
                guard placement != self.placement else { return }
                self.placement = placement
                // SwiftUI may still be laying the view out; it hears once done.
                DispatchQueue.main.async { [placementChanged] in placementChanged(placement) }
            }
        }
    }
}
