import Foundation

struct BrowserOnboardingRequest: Codable, Hashable {

    let entryPoint: BrowserOnboardingEntryPoint
    private let presentationID: UUID

    init(entryPoint: BrowserOnboardingEntryPoint, presentationID: UUID = UUID()) {
        self.entryPoint = entryPoint
        self.presentationID = presentationID
    }

    static var firstRun: Self { Self(entryPoint: .firstRun) }
    static var importBrowser: Self { Self(entryPoint: .importBrowser) }
    static var manualSetup: Self { Self(entryPoint: .manualSetup) }
}
