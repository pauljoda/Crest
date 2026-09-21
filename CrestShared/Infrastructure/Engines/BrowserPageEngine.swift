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
    func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool { false }
    var interactionState: Data? { nil }
    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool { false }
    #if os(macOS)
    var documentServices: (any BrowserPageDocumentServices)? { nil }
    func showInspector() -> Bool { false }
    func toggleInspector(_ panel: BrowserDeveloperPanel, current: BrowserDeveloperPanel?) -> BrowserWebInspectorToggleResult { .unavailable }
    #endif
}

struct BrowserEngineNavigation: Equatable, Sendable {
    let implementation: String
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
