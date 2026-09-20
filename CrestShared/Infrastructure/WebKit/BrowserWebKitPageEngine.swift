import Foundation
import Observation
import WebKit

/// The same WebKit port serves desktop and mobile. Supplemental same-document
/// history stays with its engine rather than leaking WKBackForwardListItem to UI.
@Observable @MainActor
final class BrowserWebKitPageEngine: BrowserPageEngine {
    let webView: WKWebView
    var history = BrowserPageNavigationHistory()
    var nativeView: BrowserEngineView { webView }

    init(webView: WKWebView) { self.webView = webView }

    var backHistory: [BrowserNavigationHistoryItem] {
        history.backItems.reversed().enumerated().map { Self.item($0.element, depth: $0.offset + 1) }
    }
    var forwardHistory: [BrowserNavigationHistoryItem] {
        history.forwardItems.enumerated().map { Self.item($0.element, depth: $0.offset + 1) }
    }
    func load(_ request: URLRequest) { webView.load(request) }
    func navigateHistory(by offset: Int) {
        guard offset != 0 else { return }
        history.synchronize(with: webView.backForwardList)
        let items = offset < 0 ? history.backItems : history.forwardItems
        let index = offset < 0 ? items.count + offset : offset - 1
        if items.indices.contains(index) { webView.go(to: items[index]) }
        else if offset == -1 { webView.goBack() }
        else if offset == 1 { webView.goForward() }
    }
    func reload(bypassingCache: Bool) {
        if bypassingCache { webView.reloadFromOrigin() } else { webView.reload() }
    }
    func stop() { webView.stopLoading() }
    func setZoom(_ zoom: CGFloat) { webView.pageZoom = zoom }
    func performFind(_ query: String, configuration: BrowserFindConfiguration,
                     completion: @escaping @MainActor (Bool) -> Void) {
        webView.performFind(query, configuration: configuration, completion: completion)
    }
    private static func item(_ item: WKBackForwardListItem, depth: Int) -> BrowserNavigationHistoryItem {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return BrowserNavigationHistoryItem(depth: depth,
            title: title.isEmpty ? item.url.host() ?? item.url.absoluteString : title, url: item.url)
    }
    func mediaActivity() async -> BrowserPageMediaActivity? {
        let state = await withCheckedContinuation { continuation in
            webView.requestMediaPlaybackState { continuation.resume(returning: $0) }
        }
        return BrowserPageMediaActivity(isPlaying: state == .playing,
            isCapturing: webView.cameraCaptureState != .none || webView.microphoneCaptureState != .none,
            hasPictureInPicture: false)
    }
    #if os(macOS)
    func capture(rect: CGRect?, width: CGFloat?, completion: @escaping @MainActor (NSImage?) -> Void) {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        if let rect { configuration.rect = rect }
        if let width { configuration.snapshotWidth = NSNumber(value: Double(width)) }
        webView.takeSnapshot(with: configuration) { image, _ in
            MainActor.assumeIsolated { completion(image) }
        }
    }
    #endif

}
