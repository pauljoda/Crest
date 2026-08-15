enum BrowserOnboardingFlowState: Equatable {
    case welcome
    case featureSpaces
    case featureTabs
    case featureSync
    case importSelection
    case reading(BrowserImportApplication)
    case reviewing(BrowserImportApplication)
    case committing(BrowserImportApplication)
    case manualSetup
    case complete

    var step: BrowserOnboardingStep {
        switch self {
        case .welcome:
            .welcome
        case .featureSpaces:
            .featureSpaces
        case .featureTabs:
            .featureTabs
        case .featureSync:
            .featureSync
        case .importSelection, .reading:
            .importBrowser
        case .reviewing, .committing:
            .review
        case .manualSetup:
            .manualSetup
        case .complete:
            .complete
        }
    }
}
