import Observation
import SwiftUI

/// Non-sensitive choices within Settings. Authorization and presented dialogs
/// stay with their pane and must be checked again when it is mounted.
@Observable @MainActor
final class BrowserSettingsSelections {
    var privacySpaceID: SpaceID?
    var passwordSpaceID: SpaceID?
    var extensionSpaceID: SpaceID?
    var extensionRouteRevision = 0
}

private struct BrowserSettingsSelectionsKey: EnvironmentKey {
    static let defaultValue: BrowserSettingsSelections? = nil
}

extension EnvironmentValues {
    var browserSettingsSelections: BrowserSettingsSelections? {
        get { self[BrowserSettingsSelectionsKey.self] }
        set { self[BrowserSettingsSelectionsKey.self] = newValue }
    }
}
