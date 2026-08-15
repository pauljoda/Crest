import SwiftUI

struct BrowserMacOnboardingTutorialFeature: Identifiable {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var id: String { symbol }
}
