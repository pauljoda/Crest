import Observation

@Observable
@MainActor
final class BrowserOnboardingCoordinator {
    static let sceneID = "onboarding"

    var request: BrowserOnboardingRequest = .firstRun
    var isMobilePresented = false

    func presentOnMobile(_ request: BrowserOnboardingRequest) {
        self.request = request
        isMobilePresented = true
    }
}
