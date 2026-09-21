import Foundation
import Observation
import WebKit

/// The same WebKit port serves desktop and mobile. Supplemental same-document
/// history stays with its engine rather than leaking WKBackForwardListItem to UI.
@Observable @MainActor
final class BrowserWebKitPageEngine: BrowserPageEngine {
    let registration = BrowserEngineRegistration.webKit
    let webView: WKWebView
    var history = BrowserPageNavigationHistory()
    var nativeView: BrowserEngineView { webView }

    init(webView: WKWebView) { self.webView = webView }

    var interactionState: Data? {
        guard webView.backForwardList.currentItem != nil,
            let state = webView.interactionState as? Data else { return nil }
        return BrowserEngineInteractionState(engine: "webkit",
            version: BrowserTabStateEnvelope.currentOSBuild, payload: state).encoded()
    }

    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool {
        guard let payload = BrowserEngineInteractionState.payload(state, engine: "webkit",
            version: BrowserTabStateEnvelope.currentOSBuild) else { return false }
        webView.interactionState = payload
        return webView.backForwardList.currentItem != nil
    }

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
    func showInspector() -> Bool {
        BrowserWebInspectorAccess.show(inspectorOwner: webView, isInspectable: webView.isInspectable)
    }
    func toggleInspector(_ panel: BrowserDeveloperPanel, current: BrowserDeveloperPanel?) -> BrowserWebInspectorToggleResult {
        BrowserWebInspectorAccess.toggle(panel, currentPanel: current,
            inspectorOwner: webView, isInspectable: webView.isInspectable)
    }
    // WKWebView travels with the retained page; its lifetime is not owned by an NSWindow.
    func transferOwnership(to windowID: BrowserWindowID) -> Bool { true }

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

#if os(macOS)
extension BrowserWebKitPageEngine: BrowserPageDocumentServices {
    var documentServices: (any BrowserPageDocumentServices)? { self }
    var archiveFormat: BrowserPageArchiveFormat { .webKit }

    func fullPageSnapshot(width snapshotWidth: CGFloat?) async throws -> NSImage {
        let result = try await webView.evaluateJavaScript(
            """
            (() => {
              const root = document.documentElement;
              const body = document.body;
              return [
                Math.max(root?.scrollWidth ?? 0, body?.scrollWidth ?? 0, innerWidth),
                Math.max(root?.scrollHeight ?? 0, body?.scrollHeight ?? 0, innerHeight)
              ];
            })()
            """
        )
        guard let dimensions = result as? [NSNumber],
            dimensions.count == 2
        else {
            throw BrowserDeveloperCaptureError.dimensionsUnavailable
        }

        let width = min(
            max(CGFloat(dimensions[0].doubleValue), webView.bounds.width),
            6_000
        )
        let height = min(
            max(CGFloat(dimensions[1].doubleValue), webView.bounds.height),
            24_000
        )
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        configuration.afterScreenUpdates = true
        let desiredWidth = snapshotWidth ?? min(width, 1_600)
        configuration.snapshotWidth = NSNumber(value: Double(desiredWidth))
        return try await webView.takeSnapshot(configuration: configuration)
    }
    func pdfData() async throws -> Data { try await webView.pdf(configuration: WKPDFConfiguration()) }
    func webArchiveData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            webView.createWebArchiveData { continuation.resume(with: $0) }
        }
    }
    func printOperation(with info: NSPrintInfo) async throws -> NSPrintOperation { webView.printOperation(with: info) }
}
#endif
