import Foundation

extension BrowserOnboardingProgressStore {
    static let completionKey =
        UserDefaultsBrowserOnboardingProgressPersistence.completionKey

    convenience init(
        defaults: UserDefaults? = nil,
        forceWelcome: Bool = false,
        forceSetup: Bool = false
    ) {
        let persistence: any BrowserOnboardingProgressPersisting
        if let defaults {
            persistence = UserDefaultsBrowserOnboardingProgressPersistence(
                defaults: defaults
            )
        } else if BrowserLaunchIsolationPolicy.requiresIsolation(.current) {
            persistence = InMemoryBrowserOnboardingProgressPersistence()
        } else {
            persistence = UserDefaultsBrowserOnboardingProgressPersistence()
        }
        self.init(
            persistence: persistence,
            forceWelcome: forceWelcome,
            forceSetup: forceSetup
        )
    }

    static func launchStore(
        isIsolated: Bool,
        forceWelcome: Bool,
        forceSetup: Bool
    ) -> BrowserOnboardingProgressStore {
        BrowserOnboardingProgressStore(
            persistence:
                isIsolated
                ? InMemoryBrowserOnboardingProgressPersistence(
                    hasCompletedSetup: true
                )
                : UserDefaultsBrowserOnboardingProgressPersistence(),
            forceWelcome: forceWelcome,
            forceSetup: forceSetup
        )
    }
}
