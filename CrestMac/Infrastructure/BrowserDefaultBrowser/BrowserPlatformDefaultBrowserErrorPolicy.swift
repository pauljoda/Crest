import Foundation

@MainActor
enum BrowserPlatformDefaultBrowserErrorPolicy {
    static func userFacingDescription(for error: any Error) -> String? {
        nil
    }
}
