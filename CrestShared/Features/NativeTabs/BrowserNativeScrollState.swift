import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Stores the user's position independently of a ScrollView's mounted lifetime.
@MainActor
final class BrowserNativeScrollState {
    var offset: CGFloat = 0
    #if os(macOS)
        var listRow: Int?
        var listRowOffset: CGFloat = 0
    #endif
}

private struct BrowserNativeScrollRestoration: ViewModifier {
    let state: BrowserNativeScrollState
    @State private var position: ScrollPosition
    @State private var currentOffset: CGFloat = 0

    init(state: BrowserNativeScrollState) {
        self.state = state
        _position = State(initialValue: ScrollPosition(y: state.offset))
        _currentOffset = State(initialValue: state.offset)
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onAppear {
                withTransaction(Transaction(animation: nil)) { position.scrollTo(y: state.offset) }
            }
            .onDisappear { state.offset = currentOffset }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, offset in
                currentOffset = offset
                // Capture accessibility and programmatic scrolling too. Commit
                // on disappearance so initial layout cannot erase a saved offset.
            }
    }
}

#if os(macOS)
    private struct BrowserNativeListScrollBridge: NSViewRepresentable {
        let state: BrowserNativeScrollState

        func makeNSView(context: Context) -> ObserverView { ObserverView(state: state) }
        func updateNSView(_ view: ObserverView, context: Context) { view.scheduleConnection() }

        static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.disconnect() }

        final class ObserverView: NSView {
            private let state: BrowserNativeScrollState
            private weak var clipView: NSClipView?
            private weak var tableView: NSTableView?
            private var observer: NSObjectProtocol?
            private var connectionScheduled = false
            private var isDismantled = false
            private var wasPostingBoundsChanges = false

            init(state: BrowserNativeScrollState) {
                self.state = state
                super.init(frame: .zero)
            }

            required init?(coder: NSCoder) { nil }
            override func hitTest(_ point: NSPoint) -> NSView? { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                scheduleConnection()
            }

            override func layout() {
                super.layout()
                scheduleConnection()
            }

            func scheduleConnection() {
                guard window != nil, clipView == nil, !connectionScheduled, !isDismantled else { return }
                connectionScheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.connectionScheduled = false
                    guard self.window != nil, !self.isDismantled else { return }
                    self.connect()
                }
            }

            private func connect() {
                var ancestor = superview
                while let view = ancestor {
                    if let scrollView = matchingScrollView(in: view) {
                        let clip = scrollView.contentView
                        clipView = clip
                        tableView = scrollView.documentView as? NSTableView
                        scrollView.layoutSubtreeIfNeeded()
                        var target = clip.bounds
                        target.origin.y = state.offset
                        if let tableView, let row = state.listRow, row < tableView.numberOfRows {
                            tableView.scrollRowToVisible(row)
                            tableView.layoutSubtreeIfNeeded()
                            target.origin.y = tableView.rect(ofRow: row).minY + state.listRowOffset
                        }
                        clip.scroll(to: clip.constrainBoundsRect(target).origin)
                        scrollView.reflectScrolledClipView(clip)
                        wasPostingBoundsChanges = clip.postsBoundsChangedNotifications
                        clip.postsBoundsChangedNotifications = true
                        observer = NotificationCenter.default.addObserver(
                            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                        ) { [weak self] _ in
                            MainActor.assumeIsolated {
                                guard let self, let clipView = self.clipView else { return }
                                self.state.offset = clipView.bounds.minY
                                if let tableView = self.tableView {
                                    let row = tableView.row(
                                        at: CGPoint(x: tableView.bounds.midX, y: clipView.bounds.minY))
                                    if row >= 0 {
                                        self.state.listRow = row
                                        self.state.listRowOffset =
                                            clipView.bounds.minY - tableView.rect(ofRow: row).minY
                                    }
                                }
                            }
                        }
                        return
                    }
                    ancestor = view.superview
                }
            }

            private func matchingScrollView(in view: NSView) -> NSScrollView? {
                guard view !== self, bounds.width > 0, bounds.height > 0 else { return nil }
                if let scrollView = view as? NSScrollView {
                    let viewport = scrollView.convert(scrollView.bounds, to: self)
                    if abs(viewport.minX - bounds.minX) < 2,
                        abs(viewport.minY - bounds.minY) < 2,
                        abs(viewport.width - bounds.width) < 2,
                        abs(viewport.height - bounds.height) < 2
                    {
                        return scrollView
                    }
                    return nil
                }
                for child in view.subviews {
                    if let scrollView = matchingScrollView(in: child) { return scrollView }
                }
                return nil
            }

            func disconnect() {
                isDismantled = true
                if let observer { NotificationCenter.default.removeObserver(observer) }
                clipView?.postsBoundsChangedNotifications = wasPostingBoundsChanges
                observer = nil
                clipView = nil
                tableView = nil
            }
        }
    }

    extension View {
        func browserNativeListScrollState(_ state: BrowserNativeScrollState) -> some View {
            background { BrowserNativeListScrollBridge(state: state) }
                .id(ObjectIdentifier(state))
        }
    }
#endif

extension View {
    func browserNativeScrollState(_ state: BrowserNativeScrollState) -> some View {
        modifier(BrowserNativeScrollRestoration(state: state))
            .id(ObjectIdentifier(state))
    }
}
