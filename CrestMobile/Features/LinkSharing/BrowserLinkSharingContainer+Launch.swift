import Foundation

extension BrowserLinkSharingContainer {
    // MARK: - Static Variables

    /// The container this app shares with its share extension, or nil in an
    /// isolated session, which never reads or writes the person's links.
    @MainActor
    static var app: BrowserLinkSharingContainer? {
        BrowserLaunchEnvironment.current.requiresIsolation ? nil : bundled
    }
}
