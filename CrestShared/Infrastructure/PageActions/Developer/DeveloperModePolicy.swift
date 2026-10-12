import Foundation

/// A forwarder kept only for call sites another batch owns (the CrestMobile
/// address bar and the sidebar's navigation controls). Delete this file once
/// they ask `url?.isLocalDevelopmentAddress == true` directly.
enum BrowserDeveloperModePolicy {
    static func isAutomatic(for url: URL?) -> Bool {
        url?.isLocalDevelopmentAddress == true
    }
}
