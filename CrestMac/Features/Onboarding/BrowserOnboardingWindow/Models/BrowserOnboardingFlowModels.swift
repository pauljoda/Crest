import Foundation

struct BrowserOnboardingPreparedImport {
    let passwords: [BrowserImportedPassword]
}

enum BrowserOnboardingFailureText: Equatable {
    case localized(LocalizedStringResource)
    case verbatim(String)
}

enum BrowserOnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case featureSpaces
    case featureTabs
    case featureSync
    case importBrowser
    case review
    case manualSetup
    case complete
}

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

enum BrowserOnboardingFailure: Equatable {
    case sourceUnavailable
    case dataDirectory(BrowserImportApplication)
    case read(String)
    case importCommit(String)
    case manualCommit(String)

    var message: BrowserOnboardingFailureText {
        switch self {
        case .sourceUnavailable:
            .localized(
                LocalizedStringResource(
                    "That browser is no longer available on this Mac.",
                    comment:
                        "Browser-import error shown when a selected source app disappears."
                )
            )
        case .dataDirectory(let application):
            .localized(
                LocalizedStringResource(
                    "Crest could not read \(application.name) data there. Try Allow Access again, or choose the \(application.name) data folder if it moved.",
                    comment:
                        "Browser-import error. Both variables are the source browser name."
                )
            )
        case .read(let message),
            .importCommit(let message),
            .manualCommit(let message):
            .verbatim(message)
        }
    }
}
