import Foundation

enum BrowserNavigationFailurePreviewFixture {
    static let branding = BrowserSpaceBranding(colors: [.ink, .ocean, .gold])
    static let offline = makeFailure(
        error: URLError(.notConnectedToInternet),
        phase: .provisional
    )
    static let certificate = makeFailure(
        error: URLError(.secureConnectionFailed),
        phase: .committed
    )

    private static let fallbackURL: URL = {
        guard
            let url = URL(
                string: "crest-preview://navigation.example/failure"
            )
        else {
            preconditionFailure("Navigation failure preview URL is invalid")
        }
        return url
    }()

    private static func makeFailure(
        error: URLError,
        phase: BrowserNavigationFailurePhase
    ) -> BrowserNavigationFailure {
        guard
            let failure = BrowserNavigationFailure(
                error: error,
                phase: phase,
                fallbackURL: fallbackURL
            )
        else {
            preconditionFailure("Navigation failure preview is invalid")
        }
        return failure
    }
}
