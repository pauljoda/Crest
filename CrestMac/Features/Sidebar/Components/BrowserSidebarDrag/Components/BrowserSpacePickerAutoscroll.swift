import AppKit
import SwiftUI

/// Uses the enclosing native scroll view, including manual scrolling during a
/// lift. Only its actual bounds delta is applied to the frozen reorder geometry.
struct BrowserSpacePickerAutoscroll: NSViewRepresentable {
    let viewport: CGRect
    let pointer: CGPoint?
    let contentMoved: (CGFloat) -> Void

    func makeNSView(context: Context) -> BrowserSpacePickerAutoscrollView {
        BrowserSpacePickerAutoscrollView()
    }

    func updateNSView(_ view: BrowserSpacePickerAutoscrollView, context: Context) {
        view.update(viewport: viewport, pointer: pointer, contentMoved: contentMoved)
    }

    static func dismantleNSView(_ view: BrowserSpacePickerAutoscrollView, coordinator: ()) {
        view.disconnect()
    }
}

@MainActor
final class BrowserSpacePickerAutoscrollView: NSView {
    private weak var clipView: NSClipView?
    private var observer: NSObjectProtocol?
    private var wasPostingBoundsChanges = false
    private var timer: Timer?
    private var viewport = CGRect.zero
    private var pointer: CGPoint?
    private var lastOriginX: CGFloat = 0
    private var contentMoved: ((CGFloat) -> Void)?
    private var connectionScheduled = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { disconnect() } else { connectSoon() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil { disconnect() } else { connectSoon() }
    }

    func update(viewport: CGRect, pointer: CGPoint?, contentMoved: @escaping (CGFloat) -> Void) {
        self.viewport = viewport
        self.pointer = pointer
        self.contentMoved = contentMoved
        connectSoon()
        updateTimer()
    }

    private func connectSoon() {
        guard clipView == nil, !connectionScheduled else { return }
        connectionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            connectionScheduled = false
            guard window != nil, let scrollView = enclosingScrollView else { return }
            let clip = scrollView.contentView
            clipView = clip
            lastOriginX = clip.bounds.minX
            wasPostingBoundsChanges = clip.postsBoundsChangedNotifications
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.boundsChanged() }
            }
            updateTimer()
        }
    }

    private func boundsChanged() {
        guard let clipView else { return }
        let origin = clipView.bounds.minX
        let offset = lastOriginX - origin
        lastOriginX = origin
        if pointer != nil, offset != 0 { contentMoved?(offset) }
    }

    private func updateTimer() {
        guard let pointer, clipView != nil,
            CrestSpacePickerReordering.autoscrollStep(at: pointer, in: viewport) != 0
        else {
            stopTimer()
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        timer.tolerance = 1 / 240
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advance() {
        guard let pointer, let clipView, let scrollView = clipView.enclosingScrollView,
            let document = scrollView.documentView
        else {
            stopTimer()
            return
        }
        let step = CrestSpacePickerReordering.autoscrollStep(at: pointer, in: viewport)
        guard step != 0 else {
            stopTimer()
            return
        }
        let origin = clipView.bounds.origin
        let maximum = max(document.bounds.minX, document.bounds.maxX - clipView.bounds.width)
        let newX = min(max(origin.x + step, document.bounds.minX), maximum)
        guard newX != origin.x else {
            stopTimer()
            return
        }
        clipView.scroll(to: CGPoint(x: newX, y: origin.y))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func disconnect() {
        stopTimer()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        clipView?.postsBoundsChangedNotifications = wasPostingBoundsChanges
        clipView = nil
        pointer = nil
        contentMoved = nil
    }
}
