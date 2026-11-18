import SwiftUI

/// A step of setup's walkthrough: its name, and the icon and color it shows
/// with. `BrowserSetupWalk` puts the steps in order.
struct BrowserSetupStep: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let bring = BrowserSetupStep(
        name: "bring", title: "Bring Tabs", symbol: "square.and.arrow.down.fill", color: CrestBrandPalette.sky)
    static let yourSpace = BrowserSetupStep(
        name: "yourSpace", title: "Your Space", symbol: "square.fill", color: CrestBrandPalette.coral)
    static let spaces = BrowserSetupStep(
        name: "spaces", title: "Spaces", symbol: "square.grid.2x2.fill", color: CrestBrandPalette.sage)

    static let all = [bring, yourSpace, spaces]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    /// The symbol the step shows with.
    let symbol: String
    /// The color of the tile behind the step's symbol.
    let color: Color

    var id: String { name }

    /// The identifier of the step's page.
    var accessibilityIdentifier: String { "setup-step-\(name)" }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, symbol: String, color: Color) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSetupStep, rhs: BrowserSetupStep) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
