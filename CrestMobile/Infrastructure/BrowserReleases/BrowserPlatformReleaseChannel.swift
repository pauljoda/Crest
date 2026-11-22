import StoreKit

/// The release line this build of Crest came from. The App Store signs the
/// builds it sells for production and TestFlight's for its sandbox; a build
/// from Xcode, or one whose transaction does not read, follows TestFlight,
/// which every iPhone and iPad change reaches first.
enum BrowserPlatformReleaseChannel {
    static func current() async -> BrowserReleasePage.Channel {
        if case .verified(let transaction)? = try? await AppTransaction.shared, transaction.environment == .production {
            return .appStore
        }
        return .testFlight
    }
}
