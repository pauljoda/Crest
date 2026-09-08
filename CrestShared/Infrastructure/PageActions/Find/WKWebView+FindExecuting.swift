import WebKit

extension WKWebView: BrowserFindExecuting {
    func performFind(
        _ query: String,
        configuration: WKFindConfiguration,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        find(query, configuration: configuration) { result in
            completion(result.matchFound)
        }
    }
}
