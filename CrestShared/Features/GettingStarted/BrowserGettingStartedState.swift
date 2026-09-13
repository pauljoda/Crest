import Observation

@Observable @MainActor
final class BrowserGettingStartedState {
    let practice = BrowserGettingStartedPractice()
    let scroll = BrowserNativeScrollState()
    var chapter = 0
    var lesson = 0
}
