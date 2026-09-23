import Foundation

#if os(macOS)
import AppKit
typealias BrowserEngineView = NSView
#else
import UIKit
typealias BrowserEngineView = UIView
#endif

/// The native page port used by the existing UI. The engine owns rendering and
/// navigation; portable session commands never receive a platform view.
@MainActor
protocol BrowserPageEngine: BrowserFindExecuting {
    var registration: BrowserAdapterRegistration { get }
    var nativeView: BrowserEngineView { get }
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
    func navigateHistory(by offset: Int)
    func reload(bypassingCache: Bool)
    func stop()
    var interactionState: Data? { get }
    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool
    func mediaActivity() async -> BrowserPageMediaActivity?
    /// Content bridges run by the engine itself, or nil when the page installs
    /// them through the engine's own API.
    var contentScripting: (any BrowserPageContentScripting)? { get }
    /// Applies Crest's automatic-popup decision for the current site, either to
    /// the engine's own popup blocker or to its page preferences; false when the
    /// engine has nowhere to apply it.
    func applyAutomaticPopups(_ allowed: Bool) -> Bool
    /// Applies Crest's decision for one site permission to an engine that
    /// enforces it itself: true allows, false blocks, nil leaves it to ask.
    /// False when the page enforces the decision through Crest's own bridges.
    func applySitePermission(_ permission: BrowserSitePermission, allowed: Bool?) -> Bool
    /// Ends the page's live capture after Crest withdrew the grant that allowed
    /// it. An engine that enforces site permissions itself ends capture when
    /// `applySitePermission` blocks it and needs nothing here.
    func stopMediaCapture(_ media: BrowserMediaPermission)
    /// Opens the popups the engine's blocker held back, once the person has
    /// allowed them. False when the engine keeps no such list.
    func showBlockedPopups() -> Bool
    /// Asks an engine that owns its favicon pipeline to fetch the icon again.
    func refreshFavicon()
    /// Removes the site's cookies, storage and cache. `url` names the site the
    /// page is showing, which an engine that tracks its own site may ignore;
    /// false when nothing was cleared.
    func clearSiteData(for url: URL) async -> Bool
    /// Answers a bar the engine raised for the page; false when there is no
    /// such bar.
    func respondToInfoBar(_ id: Int, response: String) -> Bool
    /// The verified server trust of the page's current document, for the
    /// certificate sheet; nil when it was not loaded over verified TLS.
    var serverTrust: SecTrust? { get }
    /// An engine that reports its own Media Session and runs its commands;
    /// nil when Crest's bridge runs in the page instead.
    var mediaSessionTransport: (any BrowserMediaSessionTransport)? { get }
    /// Runs `body` as an async function in a world of the main frame's current
    /// document that the page cannot see; nil when it produced no value.
    func evaluateInMainFrame(_ body: String) async -> Any?
    #if os(macOS)
    var documentServices: (any BrowserPageDocumentServices)? { get }
    func showInspector() -> Bool
    func toggleInspector(_ panel: BrowserDeveloperPanel, current: BrowserDeveloperPanel?) -> BrowserWebInspectorToggleResult
    /// Transfer ownership before releasing the presenting window.
    func transferOwnership(to windowID: BrowserWindowID) -> Bool
    func capture(rect: CGRect?, width: CGFloat?, completion: @escaping @MainActor (NSImage?) -> Void)
    #endif
    func setZoom(_ zoom: CGFloat)
}

extension BrowserPageEngine {
    var reportsNavigationState: Bool { false }
    @discardableResult func synchronizeHistory() -> URL? { nil }
    func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool { false }
    var interactionState: Data? { nil }
    var contentScripting: (any BrowserPageContentScripting)? { nil }
    func applyAutomaticPopups(_ allowed: Bool) -> Bool { false }
    func applySitePermission(_ permission: BrowserSitePermission, allowed: Bool?) -> Bool { false }
    func stopMediaCapture(_ media: BrowserMediaPermission) {}
    func showBlockedPopups() -> Bool { false }
    func refreshFavicon() {}
    func clearSiteData(for url: URL) async -> Bool { false }
    func respondToInfoBar(_ id: Int, response: String) -> Bool { false }
    var serverTrust: SecTrust? { nil }
    var mediaSessionTransport: (any BrowserMediaSessionTransport)? { nil }
    func evaluateInMainFrame(_ body: String) async -> Any? {
        await contentScripting?.callAsyncJavaScriptInMainFrame(body)
    }
    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool { false }
    #if os(macOS)
    var documentServices: (any BrowserPageDocumentServices)? { nil }
    func showInspector() -> Bool { false }
    func toggleInspector(_ panel: BrowserDeveloperPanel, current: BrowserDeveloperPanel?) -> BrowserWebInspectorToggleResult { .unavailable }
    #endif
}

/// Crest's answer to a site permission request an engine raised itself.
enum BrowserEnginePermissionResponse: Sendable {
    /// Allowed, and remembered for the site.
    case allow
    /// Allowed for this request only.
    case allowOnce
    /// Blocked, and remembered for the site.
    case block
    /// Not answered; the site may ask again.
    case dismiss
}

struct BrowserEngineNavigation: Equatable, Sendable {
    let implementation: BrowserEngineImplementation
    let token: String
}

#if os(macOS)
/// Rendering/export stays with the engine; save panels and print sheets stay native.
@MainActor
protocol BrowserPageDocumentServices {
    var archiveFormat: BrowserPageArchiveFormat { get }
    func fullPageSnapshot(width: CGFloat?) async throws -> NSImage
    func pdfData() async throws -> Data
    func webArchiveData() async throws -> Data
    func printOperation(with info: NSPrintInfo) async throws -> NSPrintOperation
}
#endif

struct BrowserPageMediaActivity {
    var isPlaying: Bool
    var isCapturing: Bool
    var hasPictureInPicture: Bool
}
