import Foundation

extension BrowserStore {
    /// Sends one `preferences.*` command to the core and saves the session when
    /// the record changed. A refused or unanswered command changes nothing.
    @discardableResult
    func applyAppPreferenceCommand(_ request: BrowserAppPreferenceRequest) -> Bool {
        guard family.executePreferences(request, from: self) else { return false }
        return true
    }
}
