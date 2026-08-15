import SwiftUI

struct BrowserMacOnboardingLaunchGate: View {
    let coordinator: BrowserOnboardingCoordinator

    @Environment(\.openWindow) private var openWindow
    @State private var hasOpenedSetup = false

    var body: some View {
        Color.clear
            .background(BrowserLaunchGateWindowConfigurator())
            .onAppear {
                guard !hasOpenedSetup else { return }
                hasOpenedSetup = true
                coordinator.request = .firstRun
                openWindow(id: BrowserOnboardingCoordinator.sceneID)
                BrowserOnboardingWindowActivation.bringForward()
            }
    }
}
