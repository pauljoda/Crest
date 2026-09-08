import Foundation

enum BrowserManualSetupDraftStore {
    private static let key = "BrowserManualSetupDraft"

    static func load(
        defaults: UserDefaults? = nil
    ) -> BrowserManualSetupPlan? {
        guard let defaults = launchDefaults(defaults) else { return nil }
        guard let data = defaults.data(forKey: key) else { return nil }
        guard
            let plan = try? JSONDecoder().decode(
                BrowserManualSetupPlan.self,
                from: data
            )
        else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return plan
    }

    static func save(
        _ plan: BrowserManualSetupPlan,
        defaults: UserDefaults? = nil
    ) {
        guard let defaults = launchDefaults(defaults) else { return }
        guard let data = try? JSONEncoder().encode(plan) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(defaults: UserDefaults? = nil) {
        guard let defaults = launchDefaults(defaults) else { return }
        defaults.removeObject(forKey: key)
    }

    private static func launchDefaults(
        _ explicitDefaults: UserDefaults?
    ) -> UserDefaults? {
        if let explicitDefaults { return explicitDefaults }
        guard !BrowserLaunchIsolationPolicy.requiresIsolation(.current) else {
            return nil
        }
        return .standard
    }
}
