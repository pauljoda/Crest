import AppKit
import Observation
import SwiftUI

/// The windowed shell's scrolling chrome around the shared tab list.
///
/// Two things here belong to this shell and not to the list. The list is pinned
/// to the top of a region at least as tall as the sidebar, so the space below
/// the last row is real and can be handed to `background` — which is what makes
/// the empty sidebar draggable and right-clickable. And a tap anywhere over the
/// region gives up address focus, because on this shell the address field keeps
/// it until something takes it away.
///
/// The list's sections are stacked as they are: each makes its own tab rows
/// lazily, and a lazy stack around them would size every section from an
/// estimate, which with the section's own lazy rows inside could keep the
/// sidebar's layout from ever settling. The stack keeps each section at its
/// own height, so the room left below them goes to `background` and never to
/// a row that can stretch, such as the new-tab row.
///
/// It also keeps the band of the list that is on screen, in the list's own
/// coordinates, so an open folder well away from it can be drawn as a block
/// of its own height rather than built in full. See
/// `BrowserFolderOffscreenPlaceholder`.
///
/// And it brings a tab the window just opened into view, from the frames the
/// rows register for reordering, so no row does any work for it.
struct SpaceSidebarTabListScroll<Background: View, Content: View>: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let browser: BrowserStore
    let space: SpaceModel
    @ViewBuilder let background: () -> Background
    @ViewBuilder let content: () -> Content

    @State private var scrollRegionID = UUID()
    @State private var viewport = BrowserSidebarScrollViewport()
    @State private var visibleBand = BrowserSidebarVisibleBand()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    content()
                }
                .sidebarScrollContent()
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                .background {
                    background()
                }
                .coordinateSpace(BrowserSidebarVisibleBand.contentSpace)
                .environment(\.browserSidebarVisibleBand, visibleBand)
                .environment(\.browserSidebarScrollContentSpace, BrowserSidebarVisibleBand.contentSpace)
                .background(alignment: .topLeading) {
                    // A ScrollView's outer background is a native sibling of
                    // its NSScrollView. The bridge needs the document ancestry,
                    // kept at 1x1 so it never adds a document-tall NSView.
                    BrowserSidebarDragAutoscrollObserver(
                        regionID: scrollRegionID,
                        viewport: viewport,
                        state: sidebarInteraction.sidebarReorderState
                    )
                    .frame(width: 1, height: 1)
                }
            }
            .environment(\.browserSidebarScrollRegionID, scrollRegionID)
            .onScrollGeometryChange(for: CGRect.self) {
                $0.visibleRect
            } action: { _, rect in
                visibleBand.follow(rect)
                viewport.visibleOrigin = rect.origin
                viewport.publishScrollContentOrigin(
                    for: scrollRegionID,
                    to: sidebarInteraction.sidebarReorderState
                )
            }
            .onChange(of: sidebarInteraction.sidebarReorderState.hasLiftInFlight, initial: true) { _, isLifting in
                visibleBand.hold(isLifting)
            }
            .modifier(
                SidebarScrollAffordance(
                    isDragging: sidebarInteraction.sidebarReorderState.isDragging,
                    reveal: reveal,
                    didTakeReveal: { sidebarInteraction.revealRequest = nil }
                )
            )
            .scrollClipDisabled(
                !BrowserSidebarReorderVisuals.clipsScrollableRegionWhenIdle
            )
            .background {
                BrowserSidebarScrollViewportObserver(
                    regionID: scrollRegionID,
                    viewport: viewport,
                    state: sidebarInteraction.sidebarReorderState
                )
            }
        }
        .onDisappear {
            sidebarInteraction.sidebarReorderState.removeScrollRegion(for: scrollRegionID)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                BrowserAddressFocusDismissal.dismiss()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved and current tabs")
    }

    // MARK: - Revealing

    /// The reveal this Space's list takes: the window's request for a tab it
    /// opened here, while the request is fresh. The list moves without
    /// motion while the sidebar is away, so the tab is in view when it
    /// comes back.
    private var reveal: SidebarScrollReveal? {
        guard let request = sidebarInteraction.revealRequest, request.spaceID == space.id, !request.isStale else {
            return nil
        }
        let interaction = sidebarInteraction
        let space = space
        let regionID = scrollRegionID
        let viewport = viewport
        return SidebarScrollReveal(
            id: request.id,
            animates: interaction.tabPreview.isSidebarShown,
            locate: {
                request.location(in: space, reorder: interaction.sidebarReorderState, scrollRegionID: regionID)
            },
            isHeld: { Self.isHeld(by: interaction, in: viewport.scrollView) }
        )
    }

    /// Whether the person is busy with the list in a way a reveal must not
    /// move it under: dragging from it, naming a folder, or typing in a field
    /// inside `scrollView`, such as a row's title, which its window keeps
    /// editing while Crest is in the background.
    private static func isHeld(by interaction: BrowserSidebarInteractionState, in scrollView: NSScrollView?) -> Bool {
        if interaction.sidebarReorderState.hasLiftInFlight || interaction.tabDragState.item != nil
            || interaction.folderDragState.item != nil || interaction.editingFolderRequest != nil
        {
            return true
        }
        guard let scrollView, let editor = scrollView.window?.firstResponder as? NSTextView, editor.isFieldEditor,
            let field = editor.delegate as? NSView
        else { return false }
        return field.isDescendant(of: scrollView)
    }
}

/// Only the measurement and native bridge observe the viewport. Moving a Space
/// therefore does not make the tab-list closure depend on its global frame.
@Observable
@MainActor
private final class BrowserSidebarScrollViewport {
    var frame = CGRect.zero
    /// Live scroll offset in content coordinates, kept outside `@Observable`
    /// tracking so scrolling updates `scrollContentOrigin` without invalidating
    /// views that only depend on the stationary viewport `frame`.
    @ObservationIgnored var visibleOrigin = CGPoint.zero
    /// The scroll view that hosts the list, once the bridge inside it found it.
    @ObservationIgnored weak var scrollView: NSScrollView?

    func publishScrollContentOrigin(for regionID: UUID, to state: BrowserSidebarReorderState) {
        guard !frame.isEmpty else { return }
        state.register(
            scrollContentOrigin: CGPoint(x: frame.minX - visibleOrigin.x, y: frame.minY - visibleOrigin.y),
            for: regionID
        )
    }
}

private struct BrowserSidebarScrollViewportObserver: View {
    let regionID: UUID
    let viewport: BrowserSidebarScrollViewport
    let state: BrowserSidebarReorderState

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { frame in
                viewport.frame = frame
                state.register(scrollRegionFrame: frame, for: regionID)
                viewport.publishScrollContentOrigin(for: regionID, to: state)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// AppKit owns the scroll mechanics while SwiftUI owns the list and drag. This
/// observer bridges only the live scroll offset: it advances the
/// enclosing `NSScrollView` at an edge and tells the reorder registry the exact
/// uniform translation applied to its otherwise-frozen row geometry.
private struct BrowserSidebarDragAutoscrollObserver: View {
    let regionID: UUID
    let viewport: BrowserSidebarScrollViewport
    let state: BrowserSidebarReorderState

    var body: some View {
        // The bridge lives inside the scrolling document, but its edge bands
        // use the viewport measured by the stationary outer background.
        BrowserSidebarDragAutoscrollBridge(
            regionID: regionID,
            scrollViewport: viewport,
            viewport: viewport.frame,
            pointer: state.pointer,
            isDragging: state.isDragging,
            state: state
        )
    }
}

private struct BrowserSidebarDragAutoscrollBridge: NSViewRepresentable {
    let regionID: UUID
    /// Where the bridge leaves the scroll view it finds, which a reveal reads.
    let scrollViewport: BrowserSidebarScrollViewport
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
            scrollViewport: scrollViewport,
            viewport: viewport,
            pointer: pointer,
            isDragging: isDragging,
            state: state
        )
    }

    static func dismantleNSView(_ view: BrowserSidebarDragAutoscrollObserverView, coordinator: ()) {
        view.disconnect()
    }
}

@MainActor
private final class BrowserSidebarDragAutoscrollObserverView: NSView {
    /// Thickness of the bands inside the scroll viewport that advance a long
    /// list while a lift is held at either vertical edge.
    private static let autoscrollEdgeBand: CGFloat = 56

    /// Maximum document movement per display tick at the outer edge of a band.
    private static let autoscrollMaximumStep: CGFloat = 14

    private weak var reorderState: BrowserSidebarReorderState?
    private weak var scrollViewport: BrowserSidebarScrollViewport?
    private weak var observedClipView: NSClipView?
    private var boundsObserver: NSObjectProtocol?
    private var clipViewWasPostingBoundsChanges = false
    private lazy var autoscrollClock = BrowserDragAutoscrollClock { [weak self] scale in
        self?.advanceScroll(scale: scale)
    }
    private var regionID = UUID()
    private var viewport = CGRect.zero
    private var pointer = CGPoint.zero
    private var isDragging = false
    private var lastScrollOriginY: CGFloat?
    private var connectionIsScheduled = false

    /// Signed document movement for the pointer in the scroll viewport.
    /// Negative travels toward the beginning; positive travels toward the end.
    ///
    /// The horizontal containment check is intentional. Once the pointer leaves
    /// the list for pinned tabs or other fixed chrome, that chrome owns the drop
    /// and the list behind it must stop moving.
    private var autoscrollStep: CGFloat {
        guard !viewport.isEmpty,
            pointer.x >= viewport.minX,
            pointer.x <= viewport.maxX,
            pointer.y >= viewport.minY,
            pointer.y <= viewport.maxY
        else { return 0 }

        let topDistance = pointer.y - viewport.minY
        if topDistance < Self.autoscrollEdgeBand {
            return -Self.autoscrollMaximumStep
                * (1 - topDistance / Self.autoscrollEdgeBand)
        }

        let bottomDistance = viewport.maxY - pointer.y
        if bottomDistance < Self.autoscrollEdgeBand {
            return Self.autoscrollMaximumStep
                * (1 - bottomDistance / Self.autoscrollEdgeBand)
        }

        return 0
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil { disconnect() } else { scheduleConnection() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { disconnect() } else { scheduleConnection() }
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            disconnect()
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(
        regionID: UUID,
        scrollViewport: BrowserSidebarScrollViewport,
        viewport: CGRect,
        pointer: CGPoint,
        isDragging: Bool,
        state: BrowserSidebarReorderState
    ) {
        self.regionID = regionID
        self.scrollViewport = scrollViewport
        if let scrollView = observedClipView?.enclosingScrollView { scrollViewport.scrollView = scrollView }
        self.viewport = viewport
        self.pointer = pointer
        self.isDragging = isDragging
        reorderState = state
        scheduleConnection()
        updateAutoscroll()
    }

    private func scheduleConnection() {
        guard window != nil, observedClipView == nil, !connectionIsScheduled else { return }
        connectionIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            connectionIsScheduled = false
            guard window != nil else { return }
            connectToEnclosingScrollView()
            updateAutoscroll()
        }
    }

    private func connectToEnclosingScrollView() {
        guard let scrollView = enclosingScrollView ?? nearestScrollView else {
            return
        }
        let clipView = scrollView.contentView
        scrollViewport?.scrollView = scrollView
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

    private func updateAutoscroll() {
        let step = autoscrollStep
        guard window != nil, isDragging, step != 0, observedClipView != nil else {
            autoscrollClock.stop()
            return
        }
        autoscrollClock.start(in: self)
    }

    private func advanceScroll(scale: CGFloat) {
        guard window != nil, isDragging,
            let clipView = observedClipView,
            let scrollView = clipView.enclosingScrollView,
            let documentView = scrollView.documentView
        else {
            autoscrollClock.stop()
            return
        }

        let requestedStep = autoscrollStep
        guard requestedStep != 0 else {
            autoscrollClock.stop()
            return
        }

        let step = (documentView.isFlipped ? requestedStep : -requestedStep) * scale
        let minimumY = documentView.bounds.minY
        let maximumY = max(
            minimumY,
            documentView.bounds.maxY - clipView.bounds.height
        )
        let oldOrigin = clipView.bounds.origin
        let newY = min(max(oldOrigin.y + step, minimumY), maximumY)
        guard newY != oldOrigin.y else {
            autoscrollClock.stop()
            return
        }

        clipView.scroll(to: CGPoint(x: oldOrigin.x, y: newY))
        scrollView.reflectScrolledClipView(clipView)
    }

    func disconnect() {
        autoscrollClock.stop()
        stopObservingBounds()
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
