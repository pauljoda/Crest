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
    var nativeView: BrowserEngineView { get }
    var backHistory: [BrowserNavigationHistoryItem] { get }
    var forwardHistory: [BrowserNavigationHistoryItem] { get }
    func load(_ request: URLRequest)
    func navigateHistory(by offset: Int)
    func reload(bypassingCache: Bool)
    func stop()
    func mediaActivity() async -> BrowserPageMediaActivity?
    #if os(macOS)
    /// Transfer ownership before releasing the presenting window.
    func transferOwnership(to windowID: BrowserWindowID) -> Bool
    func capture(rect: CGRect?, width: CGFloat?, completion: @escaping @MainActor (NSImage?) -> Void)
    #endif
    func setZoom(_ zoom: CGFloat)
}

struct BrowserPageMediaActivity {
    var isPlaying: Bool
    var isCapturing: Bool
    var hasPictureInPicture: Bool
}
