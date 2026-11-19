import Observation

@Observable
@MainActor
final class BrowserOnboardingCoordinator {
    var request: BrowserOnboardingRequest = .firstRun
    var isMobilePresented = false
    /// Whether Crest's browser comes up behind a phone's or iPad's setup
    /// before setup finishes, holding its own start until then, so it is
    /// ready the moment setup hands over to it.
    var preparesBrowser = false
    /// Whether setup is handing over, or handed over last: the browser shows
    /// the page it opens on behind setup, which then fades away over the same
    /// page.
    var isHandingOver = false

    func presentOnMobile(_ request: BrowserOnboardingRequest) {
        self.request = request
        isHandingOver = false
        isMobilePresented = true
    }

    /// Lets setup go, the browser in its place.
    func finishMobilePresentation() {
        isMobilePresented = false
        preparesBrowser = false
    }
}
