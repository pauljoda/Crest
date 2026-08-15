import Foundation

enum BrowserStartupPreference {
    static let key = "crest.startup.behavior"

    static func behavior(defaults: UserDefaults = .standard) -> BrowserStartupBehavior {
        guard let rawValue = defaults.string(forKey: key),
              let behavior = BrowserStartupBehavior(rawValue: rawValue) else {
            return .defaultBehavior
        }
        return behavior
    }
}
