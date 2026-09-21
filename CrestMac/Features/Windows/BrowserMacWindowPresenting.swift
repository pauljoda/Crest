/// A process host may present the existing windows itself. Commands use this
/// port without knowing the selected engine; ordinary SwiftUI scenes remain
/// the default when no host is installed at application startup.
@MainActor
protocol BrowserMacWindowPresenting: AnyObject {
    func openWindow(_ request: BrowserMacWindowRequest)
    func openOnboardingWindow(_ request: BrowserOnboardingRequest)
    func openPrivateWindow()
    func openQuickWindow(_ request: BrowserQuickWindowRequest)
}

@MainActor
enum BrowserMacWindowPresentation {
    static weak var host: (any BrowserMacWindowPresenting)?
}
