import WebKit

extension WKWebView: BrowserFindExecuting {
    func performFind(
        _ query: String,
        configuration: BrowserFindConfiguration,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let native = WKFindConfiguration()
        native.backwards = configuration.backwards
        native.caseSensitive = configuration.caseSensitive
        native.wraps = configuration.wraps
        find(query, configuration: native) { result in
            completion(result.matchFound)
        }
    }
}
