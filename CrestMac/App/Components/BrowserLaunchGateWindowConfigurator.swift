import SwiftUI

struct BrowserLaunchGateWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> BrowserLaunchGateConfigurationView {
        BrowserLaunchGateConfigurationView()
    }

    func updateNSView(
        _ nsView: BrowserLaunchGateConfigurationView,
        context: Context
    ) {
        nsView.retireWindow()
    }

    static func dismantleNSView(
        _ nsView: BrowserLaunchGateConfigurationView,
        coordinator: ()
    ) {
        // The gate is torn down the moment setup marks itself complete, which
        // can happen before or after `openCrest` restores the window by hand.
        // Restoring twice costs nothing; restoring never would leave the
        // browser off screen, so both paths ask.
        BrowserOnboardingLaunchGateWindow.restore()
    }
}
