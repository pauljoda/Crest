import Foundation

struct BrowserDataRetentionChange: Equatable, Identifiable, Sendable {
    let category: BrowserDataRetentionCategory
    let previous: BrowserDataRetentionDuration
    let proposed: BrowserDataRetentionDuration

    var id: BrowserDataRetentionCategory { category }

    var requiresConfirmation: Bool {
        guard let proposedLifetime = proposed.lifetime else { return false }
        guard let previousLifetime = previous.lifetime else { return true }
        return proposedLifetime < previousLifetime
    }
}
