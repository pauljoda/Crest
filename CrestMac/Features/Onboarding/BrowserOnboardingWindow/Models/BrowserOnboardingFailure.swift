import Foundation

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
