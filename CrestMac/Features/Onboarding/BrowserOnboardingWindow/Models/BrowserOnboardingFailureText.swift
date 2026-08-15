import Foundation

enum BrowserOnboardingFailureText: Equatable {
    case localized(LocalizedStringResource)
    case verbatim(String)
}
