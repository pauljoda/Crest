import Foundation

/// The native page port used by the existing UI: the engine's view and what it
/// shows. Everything the platform asks of the page's engine goes through its
/// `EnginePage`; portable session commands never receive a platform view.
@MainActor
protocol BrowserPageEngine: AnyObject {
    var registration: BrowserAdapterRegistration { get }
    var nativeView: BrowserEngineView { get }
    /// The entries behind and ahead of the current one, nearest first, up to
    /// `BrowserNavigationHistoryItem.listedLimit` each, however long the
    /// engine's own list is.
    var backHistory: [BrowserNavigationHistoryItem] { get }
    var forwardHistory: [BrowserNavigationHistoryItem] { get }
    /// The engine's own document URL, which can run ahead of the URL the page
    /// last observed; nil before anything loaded.
    var currentURL: URL? { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    /// True when the engine reports each navigation's state itself, so the page
    /// takes history availability and failures from those reports instead of
    /// deriving them from navigation callbacks.
    var reportsNavigationState: Bool { get }
    /// Brings supplemental history up to date with the engine's own list and
    /// answers the URL of its current entry.
    @discardableResult func synchronizeHistory() -> URL?
    func load(_ request: URLRequest)
    /// One-shot, engine-owned request metadata for a newly created native page.
    /// Tokens never enter the core session, persistence or sync.
    func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool
    /// Content bridges run by the engine itself, or nil when the page installs
    /// them through the engine's own API.
    var contentScripting: (any BrowserPageContentScripting)? { get }
}

extension BrowserPageEngine {
    var reportsNavigationState: Bool { false }
    @discardableResult func synchronizeHistory() -> URL? { nil }
    func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool { false }
    var contentScripting: (any BrowserPageContentScripting)? { nil }
}

/// A link an engine staged for a new page's first load, which keeps the
/// referrer and initiator it had where it was followed.
struct BrowserEngineNavigation: Equatable, Sendable {
    let implementation: BrowserEngineImplementation
    let token: String
    /// The core's page the link was followed in, for an engine whose staged
    /// links go through the core; nil for one that keeps them itself.
    var sourcePageID: UUID?
}
