@preconcurrency import AppKit

@MainActor
final class BrowserPeekKeyboardMonitorCoordinator: NSObject {
    var dismiss: () -> Void
    var windowNumber: Int?
    private let installsMonitor: Bool
    private var monitor: Any?

    init(
        dismiss: @escaping () -> Void,
        installsMonitor: Bool
    ) {
        self.dismiss = dismiss
        self.installsMonitor = installsMonitor
    }

    func install() {
        guard installsMonitor else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self,
                event.windowNumber == self.windowNumber,
                let action = BrowserPeekKeyboardPolicy.action(
                    forKeyCode: event.keyCode,
                    modifierFlags: BrowserKeyboardModifierFlags(
                        event.modifierFlags
                    )
                )
            else { return event }

            switch action {
            case .dismiss:
                self.dismiss()
            }
            return nil
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    isolated deinit {
        stop()
    }
}
