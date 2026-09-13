import Foundation

enum BrowserOnboardingEntryPoint: String, Codable, Hashable {
    case firstRun
    case importBrowser
    case manualSetup
    case rerun

    var isGuidedSetup: Bool {
        self == .firstRun || self == .rerun
    }
}
