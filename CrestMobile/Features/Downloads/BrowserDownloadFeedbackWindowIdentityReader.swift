import SwiftUI
import UIKit

/// Reads the identity of the window it is in.
struct BrowserDownloadFeedbackWindowIdentityReader: UIViewRepresentable {
    @Binding var identifier: ObjectIdentifier?

    func makeCoordinator() -> BrowserWindowIdentityCoordinator {
        BrowserWindowIdentityCoordinator(identifier: $identifier)
    }

    func makeUIView(context: Context) -> WindowIdentityView {
        let view = WindowIdentityView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.set(window.map(ObjectIdentifier.init))
        }
        return view
    }

    func updateUIView(_ uiView: WindowIdentityView, context: Context) {
        context.coordinator.identifier = $identifier
    }

    final class WindowIdentityView: UIView {
        var windowDidChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowDidChange?(window)
        }
    }
}
