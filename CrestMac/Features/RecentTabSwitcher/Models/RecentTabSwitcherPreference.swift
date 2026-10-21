import Foundation

/// Whether holding a Most Recent Tab shortcut shows the recent tabs, stored
/// on this Mac only. Off, both commands jump straight to a tab.
enum RecentTabSwitcherPreference {
    static let key = "crest.shortcuts.show-recent-tabs"
    static let defaultValue = true

    /// The preference as it stands now.
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }
}
