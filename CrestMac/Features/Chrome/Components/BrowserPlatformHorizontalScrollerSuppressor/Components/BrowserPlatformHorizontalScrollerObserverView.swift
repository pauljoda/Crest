import AppKit

final class BrowserPlatformHorizontalScrollerObserverView: NSView {
    private var suppressionIsScheduled = false

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleHorizontalScrollerSuppression()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleHorizontalScrollerSuppression()
    }

    override func layout() {
        super.layout()
        hideEnclosingHorizontalScroller()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func scheduleHorizontalScrollerSuppression() {
        guard !suppressionIsScheduled else { return }
        suppressionIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            suppressionIsScheduled = false
            hideEnclosingHorizontalScroller()
        }
    }

    private func hideEnclosingHorizontalScroller() {
        guard let scrollView = enclosingScrollView ?? nearestScrollView else {
            return
        }
        BrowserSpacePagerPolicy.hideHorizontalScroller(in: scrollView)
    }

    private var nearestScrollView: NSScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            ancestor = view.superview
        }
        return nil
    }
}
