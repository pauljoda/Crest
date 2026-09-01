import AppKit
import SwiftUI

/// The windowed shell's scrolling chrome around the shared tab list.
///
/// Two things here belong to this shell and not to the list. The list is laid
/// out lazily and pinned to the top of a region at least as tall as the sidebar,
/// so the space below the last row is real and can be handed to `background` —
/// which is what makes the empty sidebar draggable and right-clickable. And a
/// tap anywhere over the region gives up address focus, because on this shell
/// the address field keeps it until something takes it away.
struct SpaceSidebarTabListScroll<Background: View, Content: View>: View {
    let browser: BrowserStore
    @ViewBuilder let background: () -> Background
    @ViewBuilder let content: () -> Content

    @State private var scrollRegionID = UUID()
    @State private var scrollRegionFrame = CGRect.zero

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 0) {
                        content()
                    }

                    background()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .environment(\.browserSidebarScrollRegionID, scrollRegionID)
            .scrollClipDisabled(
                !BrowserSidebarReorderVisuals.clipsScrollableRegion(
                    clipsWhenIdle: BrowserSidebarScrollLayoutPolicy
                        .clipsScrollableRegion,
                    isDragging: browser.sidebarReorderState.isDragging
                )
            )
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { frame in
                scrollRegionFrame = frame
                browser.sidebarReorderState.register(
                    scrollRegionFrame: frame,
                    for: scrollRegionID
                )
            }
            .background {
                BrowserSidebarDragAutoscrollObserver(
                    regionID: scrollRegionID,
                    viewport: scrollRegionFrame,
                    pointer: browser.sidebarReorderState.pointer,
                    isDragging: browser.sidebarReorderState.isDragging,
                    state: browser.sidebarReorderState
                )
            }
        }
        .onDisappear {
            browser.sidebarReorderState.removeScrollRegion(for: scrollRegionID)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                BrowserAddressFocusDismissal.dismiss()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved and current tabs")
    }
}

/// AppKit owns the scroll mechanics while SwiftUI owns the list and drag. This
/// zero-sized observer bridges only the live scroll offset: it advances the
/// enclosing `NSScrollView` at an edge and tells the reorder registry the exact
/// uniform translation applied to its otherwise-frozen row geometry.
private struct BrowserSidebarDragAutoscrollObserver: NSViewRepresentable {
    let regionID: UUID
    let viewport: CGRect
    let pointer: CGPoint
    let isDragging: Bool
    let state: BrowserSidebarReorderState

    func makeNSView(context: Context) -> BrowserSidebarDragAutoscrollObserverView {
        BrowserSidebarDragAutoscrollObserverView()
    }

    func updateNSView(
        _ nsView: BrowserSidebarDragAutoscrollObserverView,
        context: Context
    ) {
        nsView.update(
            regionID: regionID,
            viewport: viewport,
            pointer: pointer,
            isDragging: isDragging,
            state: state
        )
    }
}

@MainActor
private final class BrowserSidebarDragAutoscrollObserverView: NSView {
    private weak var reorderState: BrowserSidebarReorderState?
    private weak var observedClipView: NSClipView?
    private var boundsObserver: NSObjectProtocol?
    private var clipViewWasPostingBoundsChanges = false
    private var timer: Timer?
    private var regionID = UUID()
    private var viewport = CGRect.zero
    private var pointer = CGPoint.zero
    private var isDragging = false
    private var lastScrollOriginY: CGFloat?
    private var connectionIsScheduled = false

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleConnection()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleConnection()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            stopTimer()
            stopObservingBounds()
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(
        regionID: UUID,
        viewport: CGRect,
        pointer: CGPoint,
        isDragging: Bool,
        state: BrowserSidebarReorderState
    ) {
        self.regionID = regionID
        self.viewport = viewport
        self.pointer = pointer
        self.isDragging = isDragging
        reorderState = state
        scheduleConnection()
        updateTimer()
    }

    private func scheduleConnection() {
        guard observedClipView == nil, !connectionIsScheduled else { return }
        connectionIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            connectionIsScheduled = false
            connectToEnclosingScrollView()
            updateTimer()
        }
    }

    private func connectToEnclosingScrollView() {
        guard let scrollView = enclosingScrollView ?? nearestScrollView else {
            return
        }
        let clipView = scrollView.contentView
        guard observedClipView !== clipView else { return }

        stopObservingBounds()
        observedClipView = clipView
        lastScrollOriginY = clipView.bounds.origin.y
        clipViewWasPostingBoundsChanges = clipView.postsBoundsChangedNotifications
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scrollBoundsDidChange()
            }
        }
    }

    private func scrollBoundsDidChange() {
        guard let clipView = observedClipView else { return }
        let newOriginY = clipView.bounds.origin.y
        defer { lastScrollOriginY = newOriginY }
        guard isDragging, let lastScrollOriginY else { return }
        let visualOffset = lastScrollOriginY - newOriginY
        guard visualOffset != 0 else { return }
        reorderState?.scrollableContentDidMove(
            in: regionID,
            by: visualOffset
        )
    }

    private func updateTimer() {
        let step = BrowserSidebarReorderPolicy.autoscrollStep(
            at: pointer,
            in: viewport
        )
        guard isDragging, step != 0, observedClipView != nil else {
            stopTimer()
            return
        }
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1 / 60, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceScroll()
            }
        }
        timer.tolerance = 1 / 240
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advanceScroll() {
        guard isDragging,
            let clipView = observedClipView,
            let scrollView = clipView.enclosingScrollView,
            let documentView = scrollView.documentView
        else {
            stopTimer()
            return
        }

        let requestedStep = BrowserSidebarReorderPolicy.autoscrollStep(
            at: pointer,
            in: viewport
        )
        guard requestedStep != 0 else {
            stopTimer()
            return
        }

        let step = documentView.isFlipped ? requestedStep : -requestedStep
        let minimumY = documentView.bounds.minY
        let maximumY = max(
            minimumY,
            documentView.bounds.maxY - clipView.bounds.height
        )
        let oldOrigin = clipView.bounds.origin
        let newY = min(max(oldOrigin.y + step, minimumY), maximumY)
        guard newY != oldOrigin.y else {
            stopTimer()
            return
        }

        clipView.scroll(to: CGPoint(x: oldOrigin.x, y: newY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func stopObservingBounds() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        observedClipView?.postsBoundsChangedNotifications =
            clipViewWasPostingBoundsChanges
        boundsObserver = nil
        observedClipView = nil
        clipViewWasPostingBoundsChanges = false
        lastScrollOriginY = nil
    }

    private var nearestScrollView: NSScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView { return scrollView }
            ancestor = view.superview
        }
        return nil
    }

}
