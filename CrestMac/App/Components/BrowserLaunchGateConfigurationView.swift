import SwiftUI

@MainActor
final class BrowserLaunchGateConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        retireWindow()
    }

    func retireWindow() {
        guard let window else { return }
        BrowserOnboardingLaunchGateWindow.retire(window)
    }
}
