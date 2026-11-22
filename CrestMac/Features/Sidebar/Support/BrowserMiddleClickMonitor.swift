import AppKit
import SwiftUI

/// The middle click before macOS 26, which can't attach an AppKit gesture
/// recognizer to a SwiftUI view. A view behind the row watches its window's
/// middle button and answers a press and release that both land on the part
/// of the row that is showing. It never takes a click itself.
struct BrowserMiddleClickMonitor: NSViewRepresentable {
    let perform: @MainActor () -> Void

    func makeNSView(context: Context) -> MonitoringView {
        MonitoringView(perform: perform)
    }

    func updateNSView(_ view: MonitoringView, context: Context) {
        view.perform = perform
    }

    final class MonitoringView: NSView {
        // MARK: - Static Variables

        private static let middleButton = 2

        // MARK: - Variables

        var perform: @MainActor () -> Void
        private var eventMonitor: Any?
        /// Whether the middle button went down on this row.
        private var pressBegan = false

        // MARK: - Initializers

        init(perform: @escaping @MainActor () -> Void) {
            self.perform = perform
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        // MARK: - Actions - Observation

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            pressBegan = false
            guard window != nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) {
                [weak self] event in
                self?.windowWillHandle(event)
                return event
            }
        }

        private func windowWillHandle(_ event: NSEvent) {
            guard event.window === window, event.buttonNumber == Self.middleButton else { return }
            let isOnRow = visibleRect.contains(convert(event.locationInWindow, from: nil))
            if event.type == .otherMouseDown {
                pressBegan = isOnRow
            } else if pressBegan {
                pressBegan = false
                if isOnRow { perform() }
            }
        }
    }
}
