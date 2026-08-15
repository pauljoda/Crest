enum BrowserMacOnboardingPolicy {
    static func nextFirstRunStep(
        after step: BrowserOnboardingStep
    ) -> BrowserOnboardingStep? {
        switch step {
        case .welcome:
            .featureSpaces
        case .featureSpaces:
            .featureTabs
        case .featureTabs:
            .featureSync
        case .featureSync:
            .importBrowser
        case .importBrowser, .review, .manualSetup, .complete:
            nil
        }
    }

    static func destinationAfterImport(
        for entryPoint: BrowserOnboardingEntryPoint
    ) -> BrowserOnboardingStep {
        entryPoint == .firstRun ? .manualSetup : .complete
    }
}
