enum MobileBrowserOnboardingPolicy {
    static func initialStep(
        for request: BrowserOnboardingRequest
    ) -> MobileBrowserOnboardingStep {
        switch request.entryPoint {
        case .firstRun:
            .welcome
        case .importBrowser:
            .macImport
        case .manualSetup:
            .featureSpaces
        }
    }

    static func nextStep(
        after step: MobileBrowserOnboardingStep
    ) -> MobileBrowserOnboardingStep? {
        switch step {
        case .welcome:
            .featureSpaces
        case .featureSpaces:
            .featureTabs
        case .featureTabs:
            .featureSync
        case .featureSync:
            .manualSetup
        case .manualSetup, .macImport:
            nil
        }
    }
}
