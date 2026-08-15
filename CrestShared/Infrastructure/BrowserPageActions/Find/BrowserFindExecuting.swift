import WebKit

@MainActor
protocol BrowserFindExecuting: AnyObject {
    func performFind(
        _ query: String,
        configuration: WKFindConfiguration,
        completion: @escaping @MainActor (Bool) -> Void
    )
}
