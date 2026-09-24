import Foundation

extension BrowserNavigationFailure {
    var displayHost: String {
        failingURL?.host() ?? failingURL?.absoluteString ?? "this site"
    }

    /// The error code the failure page shows, which names the problem the
    /// same way whichever engine saw it.
    var browserCode: String { kind.code }
}
