import Foundation

extension AutomationPreferencesChanged {
    @MainActor func apply(to state: CoreState) {
        state.automationPreferences = preferences
    }
}
