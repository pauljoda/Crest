import AppKit
import SwiftUI

struct BrowserMacWindowAttachment: NSViewRepresentable {
    let attach: (NSWindow) -> Void
    let focusChanged: (Bool) -> Void
    let close: () -> Void

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.attach = attach
        view.focusChanged = focusChanged
        view.close = close
        return view
    }

    func updateNSView(_ view: AttachmentView, context: Context) {}

    final class AttachmentView: NSView {
        var attach: ((NSWindow) -> Void)?
        var focusChanged: ((Bool) -> Void)?
        var close: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(becameKey), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(resignedKey), name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(willClose), name: NSWindow.willCloseNotification, object: window)
            // Scene registration and transfer can change observed models.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                self.attach?(window)
            }
        }

        @objc private func becameKey() { focusChanged?(true) }
        @objc private func resignedKey() { focusChanged?(false) }
        @objc private func willClose() { close?() }
    }
}
